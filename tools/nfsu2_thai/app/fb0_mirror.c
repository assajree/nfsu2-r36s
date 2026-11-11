/*
 * fb0_mirror.c - Real-time /dev/fb0 (/dev/tty1 fbcon) to KMSDRM Mirror Bridge
 *
 * Allows genuine Linux ncurses TUI applications (`dialog`, `whiptail`, `htop`,
 * `alsamixer`, etc.) rendered by the kernel into `/dev/fb0` via `/dev/tty1`
 * to be visible and interactive inside `playOS Terminal` (FindManager) and `playfe`.
 *
 * Key technical fixes for Rockchip RK3326 + Mali GLES2 + SDL2 KMSDRM:
 *   1. Uses `pread()` into a standard heap buffer (`ram_buf`) instead of passing
 *      an `mmap("/dev/fb0")` (`VM_IO | VM_PFNMAP`) pointer directly to OpenGL ES
 *      `glTexSubImage2D` (`SDL_UpdateTexture`), preventing Mali GPU driver `mmap_sem`
 *      page-fault deadlocks.
 *   2. Uses `SDL_PIXELFORMAT_RGB888` + `SDL_BLENDMODE_NONE` because Linux `fbcon`
 *      writes pixels to `/dev/fb0` with Alpha=0 (`[B, G, R, 0]`).
 *   3. Neutralizes SDL2's internal `/dev/tty1` fd (`SDL_EVDEV_kbd`) via `dup2()` to
 *      `/dev/null`, avoids `SDL_PollEvent()`, and restores `KDSKBMODE = K_UNICODE` +
 *      `KDSETMODE = KD_TEXT` so SDL2 cannot steal keystrokes from `dialog`.
 *   4. Translates R36H hardware gamepad events (`/dev/input/event*`) into ANSI keys
 *      (`\033[A`, `\033[B`, `\033[C`, `\033[D`, `\n`, ` `, `\t`, `\033\033`) injected into
 *      `/dev/tty1` via `ioctl(tty_fd, TIOCSTI, &c)`.
 *   5. Real-time dynamic OS button mapping (supports both playOS playfe and legacy ArkOS):
 *      - Priority 1 (playOS playfe): Reads `/home/ark/.config/playfe/playfe.cfg`:
 *          * swap_ab=true  (On)         : Button A (305) = OK (Enter) | Button B (304) = Back (Double ESC)
 *          * swap_ab=false / unset (Off): Button B (304) = OK (Enter) | Button A (305) = Back (Double ESC)
 *      - Priority 2 (Legacy ArkOS / EmulationStation, when playfe.cfg is absent):
 *          * InvertButtons=true or /var/cache/Switch_AB: Button B (304) = OK | Button A (305) = Back
 *          * Standard / Normal ES                      : Button A (305) = OK | Button B (304) = Back
 */

#include <SDL2/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <glob.h>
#include <dirent.h>
#include <signal.h>
#include <time.h>
#include <sys/ioctl.h>
#include <linux/fb.h>
#include <linux/kd.h>
#include <linux/input.h>

#define SCREEN_W 640
#define SCREEN_H 480
#define FB_PITCH (SCREEN_W * 4)
#define FB_SIZE  (FB_PITCH * SCREEN_H)

static volatile sig_atomic_t g_running = 1;

static void handle_sig(int sig) {
    (void)sig;
    g_running = 0;
}

static int ev_fds[16];
static int num_ev_fds = 0;
static int axis_x_state = 0;
static int axis_y_state = 0;

static void open_evdev_inputs(void) {
    glob_t g;
    if (glob("/dev/input/event*", 0, NULL, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc && num_ev_fds < 16; i++) {
            int fd = open(g.gl_pathv[i], O_RDONLY | O_NONBLOCK);
            if (fd >= 0) {
                ev_fds[num_ev_fds++] = fd;
            }
        }
        globfree(&g);
    }
}

static void close_evdev_inputs(void) {
    for (int i = 0; i < num_ev_fds; i++) {
        close(ev_fds[i]);
    }
    num_ev_fds = 0;
}

/* Redirect any /dev/tty* fd opened internally by SDL_EVDEV_kbd to /dev/null
 * so SDL2 cannot steal keystrokes or lock /dev/tty1 keyboard mode. */
static void detach_sdl_tty_fds(int keep_tty_fd) {
    int null_fd = open("/dev/null", O_RDWR);
    if (null_fd < 0) return;

    DIR *d = opendir("/proc/self/fd");
    if (d) {
        struct dirent *de;
        while ((de = readdir(d)) != NULL) {
            int fd = atoi(de->d_name);
            if (fd <= 2 || fd == keep_tty_fd || fd == null_fd) continue;
            char path[64], target[256];
            snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
            ssize_t len = readlink(path, target, sizeof(target) - 1);
            if (len > 0) {
                target[len] = '\0';
                if (strncmp(target, "/dev/tty", 8) == 0) {
                    dup2(null_fd, fd);
                }
            }
        }
        closedir(d);
    }
    close(null_fd);
}

static void inject_tty_str(int tty_fd, const char *s) {
    if (tty_fd < 0) return;
    while (*s) {
        char c = *s++;
        ioctl(tty_fd, TIOCSTI, &c);
    }
}

/* Dynamically resolve OK (Select) and Cancel (Back) based on active OS frontend config */
static void get_button_mapping(int *code_ok, int *code_cancel) {
    int a_is_ok = 0;
    int found_playfe = 0;

    /* 1. Priority 1: playfe configuration (/home/ark/.config/playfe/playfe.cfg) */
    FILE *fp = fopen("/home/ark/.config/playfe/playfe.cfg", "r");
    if (fp) {
        found_playfe = 1;
        a_is_ok = 0; /* playfe default (swap_ab=false or unset): B = OK, A = Back */
        char line[256];
        while (fgets(line, sizeof(line), fp)) {
            if (strncmp(line, "swap_ab=", 8) == 0) {
                if (strstr(line, "true")) {
                    a_is_ok = 1; /* On: A = OK, B = Back */
                } else {
                    a_is_ok = 0; /* Off: B = OK, A = Back */
                }
                break;
            }
        }
        fclose(fp);
    }

    /* 2. Priority 2: Fallback for pure ArkOS / EmulationStation (when playfe.cfg is absent) */
    if (!found_playfe) {
        int invert = 0;
        fp = fopen("/home/ark/.emulationstation/es_settings.cfg", "r");
        if (fp) {
            char line[256];
            while (fgets(line, sizeof(line), fp)) {
                if (strstr(line, "InvertButtons") && strstr(line, "true")) {
                    invert = 1;
                    break;
                }
            }
            fclose(fp);
        }
        if (!invert && access("/var/cache/Switch_AB", F_OK) == 0) {
            invert = 1;
        }

        /* Default in ES: A = OK (invert=0 -> a_is_ok=1). If InvertButtons=true: B = OK (a_is_ok=0) */
        a_is_ok = invert ? 0 : 1;
    }

    if (a_is_ok) {
        *code_ok = 305;     /* Button A */
        *code_cancel = 304; /* Button B */
    } else {
        *code_ok = 304;     /* Button B */
        *code_cancel = 305; /* Button A */
    }
}

static void poll_and_inject_keys(int tty_fd) {
    static int code_ok = 305;
    static int code_cancel = 304;
    static time_t s_last_check = 0;

    time_t now = time(NULL);
    if (now - s_last_check >= 1) {
        get_button_mapping(&code_ok, &code_cancel);
        s_last_check = now;
    }

    struct input_event ie;
    for (int i = 0; i < num_ev_fds; i++) {
        while (read(ev_fds[i], &ie, sizeof(ie)) == sizeof(ie)) {
            if (ie.type == EV_KEY && (ie.value == 1 || ie.value == 2)) {
                if (ie.code == 544 || ie.code == 103) { /* D-Pad UP */
                    inject_tty_str(tty_fd, "\033[A");
                } else if (ie.code == 545 || ie.code == 108) { /* D-Pad DOWN */
                    inject_tty_str(tty_fd, "\033[B");
                } else if (ie.code == 546 || ie.code == 105) { /* D-Pad LEFT */
                    inject_tty_str(tty_fd, "\033[D");
                } else if (ie.code == 547 || ie.code == 106) { /* D-Pad RIGHT */
                    inject_tty_str(tty_fd, "\033[C");
                } else if (ie.value == 1 && (ie.code == code_ok || ie.code == 705 || ie.code == 28)) {
                    /* OK / Select / Enter */
                    inject_tty_str(tty_fd, "\n");
                } else if (ie.value == 1 && (ie.code == code_cancel || ie.code == 1)) {
                    /* Cancel / Back / Exit */
                    inject_tty_str(tty_fd, "\033\033");
                } else if (ie.value == 1 && (ie.code == 307 || ie.code == 308)) {
                    /* Button X (307) or Y (308) -> Space (toggle checklist/radiolist) */
                    inject_tty_str(tty_fd, " ");
                } else if (ie.value == 1 && ie.code == 704) {
                    /* SELECT (704) -> TAB */
                    inject_tty_str(tty_fd, "\t");
                }
            } else if (ie.type == EV_ABS) {
                if (ie.code == 1 || ie.code == 17) {
                    if (ie.value <= -600 || (ie.code == 17 && ie.value < 0)) {
                        if (axis_y_state != -1) {
                            axis_y_state = -1;
                            inject_tty_str(tty_fd, "\033[A");
                        }
                    } else if (ie.value >= 600 || (ie.code == 17 && ie.value > 0)) {
                        if (axis_y_state != 1) {
                            axis_y_state = 1;
                            inject_tty_str(tty_fd, "\033[B");
                        }
                    } else if (ie.value > -300 && ie.value < 300) {
                        axis_y_state = 0;
                    }
                } else if (ie.code == 0 || ie.code == 16) {
                    if (ie.value <= -600 || (ie.code == 16 && ie.value < 0)) {
                        if (axis_x_state != -1) {
                            axis_x_state = -1;
                            inject_tty_str(tty_fd, "\033[D");
                        }
                    } else if (ie.value >= 600 || (ie.code == 16 && ie.value > 0)) {
                        if (axis_x_state != 1) {
                            axis_x_state = 1;
                            inject_tty_str(tty_fd, "\033[C");
                        }
                    } else if (ie.value > -300 && ie.value < 300) {
                        axis_x_state = 0;
                    }
                }
            }
        }
    }
}

int main(void) {
    signal(SIGTERM, handle_sig);
    signal(SIGINT, handle_sig);

    int fb_fd = open("/dev/fb0", O_RDONLY);
    if (fb_fd < 0) {
        perror("open /dev/fb0");
        return 1;
    }

    unsigned char *ram_buf = (unsigned char *)malloc(FB_SIZE);
    if (!ram_buf) {
        close(fb_fd);
        return 1;
    }
    memset(ram_buf, 0, FB_SIZE);

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "SDL_Init error: %s\n", SDL_GetError());
        free(ram_buf);
        close(fb_fd);
        return 1;
    }

    SDL_Window *win = SDL_CreateWindow("fb0_mirror",
                                       SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                       SCREEN_W, SCREEN_H,
                                       SDL_WINDOW_SHOWN | SDL_WINDOW_FULLSCREEN);
    if (!win) {
        SDL_Quit();
        free(ram_buf);
        close(fb_fd);
        return 1;
    }

    SDL_Renderer *rend = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!rend) {
        rend = SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE);
    }

    SDL_Texture *tex = SDL_CreateTexture(rend,
                                         SDL_PIXELFORMAT_RGB888,
                                         SDL_TEXTUREACCESS_STREAMING,
                                         SCREEN_W, SCREEN_H);
    SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_NONE);

    /* Open our own /dev/tty1 handle AFTER SDL_Init and neutralize SDL2's internal /dev/tty1 fd */
    int tty_fd = open("/dev/tty1", O_RDWR | O_NOCTTY);
    detach_sdl_tty_fds(tty_fd);

    if (tty_fd >= 0) {
        ioctl(tty_fd, KDSETMODE, KD_TEXT);
        ioctl(tty_fd, KDSKBMODE, K_UNICODE);
    }

    const char *no_input_env = getenv("FB0_NO_INPUT");
    int enable_input = (!no_input_env || strcmp(no_input_env, "1") != 0);
    if (enable_input) {
        open_evdev_inputs();
    }

    /* Drain any initial button release */
    SDL_Delay(200);
    struct input_event ie;
    for (int i = 0; i < num_ev_fds; i++) {
        while (read(ev_fds[i], &ie, sizeof(ie)) > 0) {}
    }

    while (g_running) {
        /* Do NOT call SDL_PollEvent() here so SDL_EVDEV_kbd never drains /dev/tty1 */
        if (tty_fd >= 0) {
            int mode = KD_TEXT;
            if (ioctl(tty_fd, KDGETMODE, &mode) == 0 && mode != KD_TEXT) {
                ioctl(tty_fd, KDSETMODE, KD_TEXT);
            }
            int kbmode = K_UNICODE;
            if (ioctl(tty_fd, KDGKBMODE, &kbmode) == 0 && kbmode != K_UNICODE && kbmode != K_XLATE) {
                ioctl(tty_fd, KDSKBMODE, K_UNICODE);
            }
        }

        if (enable_input && tty_fd >= 0) {
            poll_and_inject_keys(tty_fd);
        }

        if (pread(fb_fd, ram_buf, FB_SIZE, 0) > 0) {
            SDL_UpdateTexture(tex, NULL, ram_buf, FB_PITCH);
            SDL_RenderCopy(rend, tex, NULL, NULL);
            SDL_RenderPresent(rend);
        }

        SDL_Delay(16);
    }

    SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(rend);
    SDL_DestroyWindow(win);
    SDL_Quit();

    close_evdev_inputs();
    if (tty_fd >= 0) {
        ioctl(tty_fd, KDSETMODE, KD_TEXT);
        ioctl(tty_fd, KDSKBMODE, K_UNICODE);
        close(tty_fd);
    }
    free(ram_buf);
    close(fb_fd);
    return 0;
}
