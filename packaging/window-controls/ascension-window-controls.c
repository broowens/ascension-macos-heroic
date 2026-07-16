#define _WIN32_WINNT 0x0600
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

typedef LRESULT (CALLBACK *hook_proc)(int, WPARAM, LPARAM);

struct hook_context {
    HMODULE module;
    hook_proc procedure;
    BOOL found_launcher;
    BOOL found_game;
    HWND launcher_window;
};

static BOOL window_belongs_to_game(HWND window)
{
    DWORD process_id;
    HANDLE process;
    char path[1024];
    DWORD length = sizeof(path);
    char *file_name;
    BOOL matches = FALSE;

    GetWindowThreadProcessId(window, &process_id);
    process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
    if (process == NULL) {
        return FALSE;
    }
    if (QueryFullProcessImageNameA(process, 0, path, &length)) {
        file_name = strrchr(path, '\\');
        file_name = file_name != NULL ? file_name + 1 : path;
        matches = lstrcmpiA(file_name, "Ascension.exe") == 0 ||
            lstrcmpiA(file_name, "MMgr64.exe") == 0;
    }
    CloseHandle(process);
    return matches;
}

static BOOL CALLBACK enable_launcher_close(HWND window, LPARAM raw_context)
{
    struct hook_context *context = (struct hook_context *) raw_context;
    char title[256];
    DWORD thread_id;
    HHOOK hook;
    DWORD_PTR result;

    if (window_belongs_to_game(window)) {
        context->found_game = TRUE;
    }
    if (GetWindowTextA(window, title, sizeof(title)) == 0 ||
        lstrcmpA(title, "Ascension Launcher") != 0) {
        return TRUE;
    }
    context->found_launcher = TRUE;
    context->launcher_window = window;

    thread_id = GetWindowThreadProcessId(window, NULL);
    hook = SetWindowsHookExA(WH_CALLWNDPROC, context->procedure, context->module, thread_id);
    if (hook != NULL) {
        SendMessageTimeoutA(window, WM_NULL, 0, 0, SMTO_ABORTIFHUNG, 1000, &result);
        UnhookWindowsHookEx(hook);
    }

    return TRUE;
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR command_line, int show)
{
    struct hook_context context;
    union {
        FARPROC raw;
        hook_proc typed;
    } hook_symbol;
    char module_path[MAX_PATH];
    char *file_name;
    BOOL saw_launcher = FALSE;
    BOOL saw_game = FALSE;
    BOOL hidden_by_helper = FALSE;
    BOOL close_requested = FALSE;
    BOOL close_while_playing;
    BOOL hide_while_playing;
    BOOL show_after_game;
    unsigned int missing_checks = 0;

    (void) instance;
    (void) previous;
    (void) show;

    close_while_playing = strstr(command_line, "--close-launcher-while-playing") != NULL;
    hide_while_playing = strstr(command_line, "--hide-launcher-while-playing") != NULL;
    show_after_game = strstr(command_line, "--show-launcher-after-game") != NULL;

    if (GetModuleFileNameA(NULL, module_path, sizeof(module_path)) == 0) {
        return 1;
    }
    file_name = strrchr(module_path, '\\');
    if (file_name == NULL) {
        return 1;
    }
    lstrcpyA(file_name + 1, "ascension-window-hook.dll");

    context.module = LoadLibraryA(module_path);
    if (context.module == NULL) {
        return 1;
    }
    hook_symbol.raw = GetProcAddress(context.module, "EnableCloseHook");
    context.procedure = hook_symbol.typed;
    if (context.procedure == NULL) {
        FreeLibrary(context.module);
        return 1;
    }

    for (;;) {
        context.found_launcher = FALSE;
        context.found_game = FALSE;
        context.launcher_window = NULL;
        EnumWindows(enable_launcher_close, (LPARAM) &context);
        if (context.found_launcher) {
            saw_launcher = TRUE;
            missing_checks = 0;
        } else if (saw_launcher && ++missing_checks >= 10) {
            break;
        }

        if (context.found_game) {
            saw_game = TRUE;
            if (close_while_playing && !close_requested && context.launcher_window != NULL) {
                DWORD_PTR result;
                /* Follow the launcher's normal close path. Do not terminate
                 * Wine's process tree because the game is its descendant. */
                SendMessageTimeoutA(context.launcher_window, WM_SYSCOMMAND, SC_CLOSE, 0,
                    SMTO_ABORTIFHUNG, 2000, &result);
                close_requested = TRUE;
            } else if (hide_while_playing && context.launcher_window != NULL &&
                IsWindowVisible(context.launcher_window)) {
                /* Tell Chromium the launcher is minimized before hiding it so
                 * its renderers can enter their background-throttled state. */
                ShowWindow(context.launcher_window, SW_MINIMIZE);
                Sleep(100);
                ShowWindow(context.launcher_window, SW_HIDE);
                hidden_by_helper = TRUE;
            }
        } else if (saw_game && hidden_by_helper && show_after_game &&
                   context.launcher_window != NULL) {
            ShowWindow(context.launcher_window, SW_SHOW);
            ShowWindow(context.launcher_window, SW_RESTORE);
            SetForegroundWindow(context.launcher_window);
            hidden_by_helper = FALSE;
            saw_game = FALSE;
        }
        Sleep(500);
    }

    FreeLibrary(context.module);
    return 0;
}
