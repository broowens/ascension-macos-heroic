#define WIN32_LEAN_AND_MEAN
#include <windows.h>

__declspec(dllexport) LRESULT CALLBACK EnableCloseHook(int code, WPARAM word, LPARAM raw_message)
{
    if (code >= 0 && raw_message != 0) {
        const CWPSTRUCT *message = (const CWPSTRUCT *) raw_message;
        HWND window = GetAncestor(message->hwnd, GA_ROOT);
        char title[256];

        if (window != NULL && GetWindowTextA(window, title, sizeof(title)) > 0 &&
            lstrcmpA(title, "Ascension Launcher") == 0) {
            LONG_PTR style = GetWindowLongPtrA(window, GWL_STYLE);
            HMENU menu;

            if ((style & WS_SYSMENU) == 0) {
                SetWindowLongPtrA(window, GWL_STYLE, style | WS_SYSMENU);
                SetWindowPos(window, NULL, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
            }

            menu = GetSystemMenu(window, FALSE);
            if (menu != NULL) {
                EnableMenuItem(menu, SC_CLOSE, MF_BYCOMMAND | MF_ENABLED);
                DrawMenuBar(window);
            }
        }
    }

    return CallNextHookEx(NULL, code, word, raw_message);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void) instance;
    (void) reason;
    (void) reserved;
    return TRUE;
}
