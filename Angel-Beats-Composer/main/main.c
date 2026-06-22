#include <windows.h>
#include <commctrl.h>
#include <gdiplus.h>
#include "cracker_core.h"
#include <process.h>

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "comctl32.lib")

// 资源ID定义
#define IDC_BTN_START       1001
#define IDC_BTN_STOP        1002
#define IDC_BTN_SELECT_HASH 1003
#define IDC_BTN_SELECT_DICT 1004
#define IDC_BTN_OUTPUT      1005
#define IDC_COMBO_THEME     1006
#define IDC_COMBO_ATK       1007
#define IDC_COMBO_HASH      1008
#define IDC_EDIT_MAXLEN     1009
#define IDC_EDIT_CHARSET    1010
#define IDC_CHECK_RESUME    1011
#define IDC_PROGRESS_BAR    1012
#define IDC_STATIC_STATUS   1013
#define IDC_LIST_RESULT     1014
#define IDC_EDIT_HASHFILE   1015
#define IDC_EDIT_DICTFILE   1016
#define IDC_EDIT_OUTFILE    1017

// 全局GUI句柄
HWND g_hWnd;
HWND g_hProgress;
HWND g_hStatus;
HWND g_hListResult;
HANDLE g_hCrackThread = NULL;
volatile int g_cracking = 0;

// GDI+ 资源
ULONG_PTR g_gdiplusToken;
Gdiplus::GdiplusStartupInput g_gdiplusStartupInput;

// 主题图像（从资源加载）
HBITMAP g_hThemeImages[4];

// 窗口过程前向声明
LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
void UpdateTheme(int theme);
void StartCracking(void);
void StopCracking(void);
DWORD WINAPI CrackThreadProc(LPVOID lpParam);
void AppendResultText(const char* text);
void UpdateProgress(int percent, const char* status);

// 加载主题图像（使用GDI+从资源或文件加载）
HBITMAP LoadImageFromResource(int resId) {
    // 简化：从文件加载，实际应用中可使用 LoadImage 或 GDI+ 从资源加载
    return (HBITMAP)LoadImage(GetModuleHandle(NULL), MAKEINTRESOURCE(resId), IMAGE_BITMAP, 0, 0, LR_DEFAULTCOLOR);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    // 初始化通用控件
    INITCOMMONCONTROLSEX icex;
    icex.dwSize = sizeof(INITCOMMONCONTROLSEX);
    icex.dwICC = ICC_PROGRESS_CLASS | ICC_LISTVIEW_CLASSES;
    InitCommonControlsEx(&icex);

    // 初始化GDI+
    Gdiplus::GdiplusStartup(&g_gdiplusToken, &g_gdiplusStartupInput, NULL);

    // 注册窗口类
    WNDCLASSEX wc = {0};
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = L"HashCrackerClass";
    RegisterClassEx(&wc);

    // 创建窗口
    g_hWnd = CreateWindowEx(0, L"HashCrackerClass", L"主题哈希破解工具 - 阴阳师/深空之眼/重返未来1999/雷索纳斯",
                            WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
                            NULL, NULL, hInstance, NULL);
    ShowWindow(g_hWnd, nCmdShow);
    UpdateWindow(g_hWnd);

    // 加载主题图像（假设资源中有位图 IDB_YINYANG 等）
    // 此处简化，实际需要添加资源文件
    for (int i = 0; i < 4; i++)
        g_hThemeImages[i] = NULL;

    // 消息循环
    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    Gdiplus::GdiplusShutdown(g_gdiplusToken);
    return msg.wParam;
}

// 创建所有控件
void CreateControls(HWND hWnd) {
    // 主题选择
    CreateWindow(L"STATIC", L"主题:", WS_CHILD | WS_VISIBLE, 10, 10, 50, 20, hWnd, NULL, NULL, NULL);
    HWND hComboTheme = CreateWindow(L"COMBOBOX", NULL, WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST, 70, 8, 150, 100,
                                    hWnd, (HMENU)IDC_COMBO_THEME, NULL, NULL);
    SendMessage(hComboTheme, CB_ADDSTRING, 0, (LPARAM)L"阴阳师·休闲养老");
    SendMessage(hComboTheme, CB_ADDSTRING, 0, (LPARAM)L"深空之眼·动作战斗");
    SendMessage(hComboTheme, CB_ADDSTRING, 0, (LPARAM)L"重返未来1999·时间旅行");
    SendMessage(hComboTheme, CB_ADDSTRING, 0, (LPARAM)L"雷索纳斯·频率共振");
    SendMessage(hComboTheme, CB_SETCURSEL, 0, 0);

    // 攻击模式
    CreateWindow(L"STATIC", L"攻击模式:", WS_CHILD | WS_VISIBLE, 10, 40, 60, 20, hWnd, NULL, NULL, NULL);
    HWND hComboAtk = CreateWindow(L"COMBOBOX", NULL, WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST, 80, 38, 100, 100,
                                  hWnd, (HMENU)IDC_COMBO_ATK, NULL, NULL);
    SendMessage(hComboAtk, CB_ADDSTRING, 0, (LPARAM)L"字典攻击");
    SendMessage(hComboAtk, CB_ADDSTRING, 0, (LPARAM)L"暴力破解");
    SendMessage(hComboAtk, CB_SETCURSEL, 0, 0);

    // 哈希类型
    CreateWindow(L"STATIC", L"哈希算法:", WS_CHILD | WS_VISIBLE, 10, 70, 60, 20, hWnd, NULL, NULL, NULL);
    HWND hComboHash = CreateWindow(L"COMBOBOX", NULL, WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST, 80, 68, 100, 100,
                                   hWnd, (HMENU)IDC_COMBO_HASH, NULL, NULL);
    SendMessage(hComboHash, CB_ADDSTRING, 0, (LPARAM)L"MD5");
    SendMessage(hComboHash, CB_ADDSTRING, 0, (LPARAM)L"SHA1");
    SendMessage(hComboHash, CB_ADDSTRING, 0, (LPARAM)L"SHA256");
    SendMessage(hComboHash, CB_SETCURSEL, 0, 0);

    // 哈希文件选择
    CreateWindow(L"STATIC", L"哈希文件:", WS_CHILD | WS_VISIBLE, 10, 100, 60, 20, hWnd, NULL, NULL, NULL);
    CreateWindow(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER, 80, 98, 300, 22, hWnd, (HMENU)IDC_EDIT_HASHFILE, NULL, NULL);
    CreateWindow(L"BUTTON", L"浏览...", WS_CHILD | WS_VISIBLE, 390, 98, 60, 22, hWnd, (HMENU)IDC_BTN_SELECT_HASH, NULL, NULL);

    // 字典文件（仅字典模式）
    CreateWindow(L"STATIC", L"字典文件:", WS_CHILD | WS_VISIBLE, 10, 130, 60, 20, hWnd, NULL, NULL, NULL);
    CreateWindow(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER, 80, 128, 300, 22, hWnd, (HMENU)IDC_EDIT_DICTFILE, NULL, NULL);
    CreateWindow(L"BUTTON", L"浏览...", WS_CHILD | WS_VISIBLE, 390, 128, 60, 22, hWnd, (HMENU)IDC_BTN_SELECT_DICT, NULL, NULL);

    // 输出文件
    CreateWindow(L"STATIC", L"输出文件:", WS_CHILD | WS_VISIBLE, 10, 160, 60, 20, hWnd, NULL, NULL, NULL);
    CreateWindow(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER, 80, 158, 300, 22, hWnd, (HMENU)IDC_EDIT_OUTFILE, NULL, NULL);
    CreateWindow(L"BUTTON", L"浏览...", WS_CHILD | WS_VISIBLE, 390, 158, 60, 22, hWnd, (HMENU)IDC_BTN_OUTPUT, NULL, NULL);

    // 暴力破解参数
    CreateWindow(L"STATIC", L"最大长度:", WS_CHILD | WS_VISIBLE, 10, 190, 60, 20, hWnd, NULL, NULL, NULL);
    CreateWindow(L"EDIT", L"4", WS_CHILD | WS_VISIBLE | WS_BORDER, 80, 188, 60, 22, hWnd, (HMENU)IDC_EDIT_MAXLEN, NULL, NULL);
    CreateWindow(L"STATIC", L"字符集:", WS_CHILD | WS_VISIBLE, 160, 190, 50, 20, hWnd, NULL, NULL, NULL);
    CreateWindow(L"EDIT", L"abcdefghijklmnopqrstuvwxyz0123456789", WS_CHILD | WS_VISIBLE | WS_BORDER, 220, 188, 200, 22, hWnd, (HMENU)IDC_EDIT_CHARSET, NULL, NULL);
    CreateWindow(L"BUTTON", L"断点续传", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 440, 190, 80, 22, hWnd, (HMENU)IDC_CHECK_RESUME, NULL, NULL);

    // 按钮
    CreateWindow(L"BUTTON", L"开始破解", WS_CHILD | WS_VISIBLE, 10, 220, 100, 30, hWnd, (HMENU)IDC_BTN_START, NULL, NULL);
    CreateWindow(L"BUTTON", L"停止", WS_CHILD | WS_VISIBLE, 120, 220, 80, 30, hWnd, (HMENU)IDC_BTN_STOP, NULL, NULL);

    // 进度条
    g_hProgress = CreateWindow(PROGRESS_CLASS, NULL, WS_CHILD | WS_VISIBLE, 10, 260, 500, 20, hWnd, (HMENU)IDC_PROGRESS_BAR, NULL, NULL);
    SendMessage(g_hProgress, PBM_SETRANGE, 0, MAKELPARAM(0, 100));

    // 状态文本
    g_hStatus = CreateWindow(L"STATIC", L"就绪", WS_CHILD | WS_VISIBLE, 10, 290, 500, 20, hWnd, (HMENU)IDC_STATIC_STATUS, NULL, NULL);

    // 结果列表
    g_hListResult = CreateWindow(L"LISTBOX", NULL, WS_CHILD | WS_VISIBLE | WS_BORDER | WS_VSCROLL | LBS_NOTIFY,
                                 10, 320, 760, 230, hWnd, (HMENU)IDC_LIST_RESULT, NULL, NULL);
}

// 更新界面主题（改变背景色或显示图像）
void UpdateTheme(int theme) {
    // 可根据 theme 改变窗口背景或显示主题图片
    // 为简化，改变状态栏文字颜色等
    const wchar_t* themeNames[] = {L"阴阳师·休闲养老", L"深空之眼·动作战斗", L"重返未来1999·时间旅行", L"雷索纳斯·频率共振"};
    SetWindowText(g_hStatus, themeNames[theme]);
    // 实际可以设置窗口背景刷子或绘制图像
    InvalidateRect(g_hWnd, NULL, TRUE);
}

// 在WM_PAINT中绘制主题图像
void DrawThemeImage(HDC hdc, RECT* rect) {
    // 根据当前主题绘制图像（从资源加载的HBITMAP）
    int theme = SendDlgItemMessage(g_hWnd, IDC_COMBO_THEME, CB_GETCURSEL, 0, 0);
    if (g_hThemeImages[theme]) {
        HDC hdcMem = CreateCompatibleDC(hdc);
        SelectObject(hdcMem, g_hThemeImages[theme]);
        BITMAP bm;
        GetObject(g_hThemeImages[theme], sizeof(BITMAP), &bm);
        // 绘制在右上角
        StretchBlt(hdc, rect->right - bm.bmWidth - 10, rect->top + 10, bm.bmWidth, bm.bmHeight, hdcMem, 0, 0, bm.bmWidth, bm.bmHeight, SRCCOPY);
        DeleteDC(hdcMem);
    }
}

// 启动破解线程
void StartCracking(void) {
    if (g_cracking) return;

    // 从界面收集配置
    int themeIdx = SendDlgItemMessage(g_hWnd, IDC_COMBO_THEME, CB_GETCURSEL, 0, 0);
    int atkIdx = SendDlgItemMessage(g_hWnd, IDC_COMBO_ATK, CB_GETCURSEL, 0, 0);
    int hashIdx = SendDlgItemMessage(g_hWnd, IDC_COMBO_HASH, CB_GETCURSEL, 0, 0);

    g_config.theme = (Theme)themeIdx;
    g_config.attack_mode = (atkIdx == 0) ? ATTACK_DICT : ATTACK_BRUTE;
    g_config.hash_type = (HashType)hashIdx;
    GetWindowText(GetDlgItem(g_hWnd, IDC_EDIT_HASHFILE), g_config.hash_file, MAX_PATH);
    GetWindowText(GetDlgItem(g_hWnd, IDC_EDIT_DICTFILE), g_config.dict_file, MAX_PATH);
    GetWindowText(GetDlgItem(g_hWnd, IDC_EDIT_OUTFILE), g_config.output_file, MAX_PATH);
    char buf[32];
    GetWindowText(GetDlgItem(g_hWnd, IDC_EDIT_MAXLEN), buf, 32);
    g_config.brute_max_len = atoi(buf);
    GetWindowText(GetDlgItem(g_hWnd, IDC_EDIT_CHARSET), g_config.brute_charset, 96);
    g_config.resume = (IsDlgButtonChecked(g_hWnd, IDC_CHECK_RESUME) == BST_CHECKED);
    g_config.thread_count = 4; // 可从界面读取

    // 重置全局状态
    g_should_exit = 0;
    g_cracked_count = 0;
    // 释放旧哈希链表并重新加载
    while (g_hash_list) {
        HashNode* tmp = g_hash_list->next;
        free(g_hash_list);
        g_hash_list = tmp;
    }
    g_total_hashes = 0;
    load_hashes(g_config.hash_file);
    if (g_total_hashes == 0) {
        AppendResultText("错误：无法加载哈希文件或文件为空");
        return;
    }

    g_cracking = 1;
    EnableWindow(GetDlgItem(g_hWnd, IDC_BTN_START), FALSE);
    EnableWindow(GetDlgItem(g_hWnd, IDC_BTN_STOP), TRUE);
    UpdateProgress(0, "正在破解...");
    g_hCrackThread = CreateThread(NULL, 0, CrackThreadProc, NULL, 0, NULL);
}

// 停止破解
void StopCracking(void) {
    if (g_cracking) {
        g_should_exit = 1;
        AppendResultText("用户停止破解...");
        UpdateProgress(0, "已停止");
    }
}

// 破解线程函数
DWORD WINAPI CrackThreadProc(LPVOID lpParam) {
    run_cracker();
    // 完成后更新界面
    PostMessage(g_hWnd, WM_APP, 0, 0);
    return 0;
}

// 向结果列表添加文本
void AppendResultText(const char* text) {
    // 转换为宽字符
    wchar_t wtext[512];
    MultiByteToWideChar(CP_UTF8, 0, text, -1, wtext, 512);
    SendMessage(g_hListResult, LB_ADDSTRING, 0, (LPARAM)wtext);
    SendMessage(g_hListResult, LB_SETTOPINDEX, SendMessage(g_hListResult, LB_GETCOUNT, 0, 0) - 1, 0);
}

// 更新进度条和状态
void UpdateProgress(int percent, const char* status) {
    SendMessage(g_hProgress, PBM_SETPOS, percent, 0);
    wchar_t wstatus[256];
    MultiByteToWideChar(CP_UTF8, 0, status, -1, wstatus, 256);
    SetWindowText(g_hStatus, wstatus);
}

// 文件浏览对话框
void BrowseFile(HWND hEdit, const wchar_t* filter) {
    OPENFILENAME ofn = {0};
    wchar_t filename[MAX_PATH] = {0};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = g_hWnd;
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = filename;
    ofn.nMaxFile = MAX_PATH;
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
    if (GetOpenFileName(&ofn)) {
        SetWindowText(hEdit, filename);
    }
}

// 窗口过程
LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE:
        CreateControls(hWnd);
        break;
    case WM_COMMAND:
        switch (LOWORD(wParam)) {
        case IDC_BTN_START: StartCracking(); break;
        case IDC_BTN_STOP: StopCracking(); break;
        case IDC_BTN_SELECT_HASH: BrowseFile(GetDlgItem(hWnd, IDC_EDIT_HASHFILE), L"文本文件\0*.txt\0所有文件\0*.*\0"); break;
        case IDC_BTN_SELECT_DICT: BrowseFile(GetDlgItem(hWnd, IDC_EDIT_DICTFILE), L"字典文件\0*.txt\0*.*\0"); break;
        case IDC_BTN_OUTPUT: BrowseFile(GetDlgItem(hWnd, IDC_EDIT_OUTFILE), L"文本文件\0*.txt\0*.*\0"); break;
        case IDC_COMBO_THEME:
            if (HIWORD(wParam) == CBN_SELCHANGE) {
                int theme = SendMessage((HWND)lParam, CB_GETCURSEL, 0, 0);
                UpdateTheme(theme);
            }
            break;
        }
        break;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hWnd, &ps);
        // 绘制背景图像（可选）
        RECT rc;
        GetClientRect(hWnd, &rc);
        DrawThemeImage(hdc, &rc);
        EndPaint(hWnd, &ps);
        break;
    }
    case WM_APP:  // 破解完成消息
        g_cracking = 0;
        EnableWindow(GetDlgItem(hWnd, IDC_BTN_START), TRUE);
        EnableWindow(GetDlgItem(hWnd, IDC_BTN_STOP), FALSE);
        UpdateProgress(100, "破解完成");
        AppendResultText("破解过程结束，结果已保存");
        save_results();
        // 在列表中显示破解结果
        for (HashNode* node = g_hash_list; node; node = node->next) {
            char line[256];
            if (node->plain[0])
                sprintf(line, "[成功] %s -> %s", node->hash, node->plain);
            else
                sprintf(line, "[失败] %s", node->hash);
            AppendResultText(line);
        }
        break;
    case WM_DESTROY:
        StopCracking();
        if (g_hCrackThread) WaitForSingleObject(g_hCrackThread, 3000);
        for (int i = 0; i < 4; i++)
            if (g_hThemeImages[i]) DeleteObject(g_hThemeImages[i]);
        PostQuitMessage(0);
        break;
    default:
        return DefWindowProc(hWnd, msg, wParam, lParam);
    }
    return 0;
}