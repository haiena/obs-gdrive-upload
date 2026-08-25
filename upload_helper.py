#!/usr/bin/env python3
"""
出貨測試影片上傳 helper。

由 obs_gdrive_upload.py 在錄影結束時呼叫，也可以手動執行來補傳：
    python3 upload_helper.py --file /path/to/video.mkv --remote "gdrive:出貨測試影片"

流程：
  1. 等待檔案大小穩定（OBS 停止錄影後仍可能在收尾）
  2. 彈出視窗要求輸入單號
  3. 組出 單號_YYYYMMDD_HHMMSS.副檔名
  4. rclone moveto / copyto 上傳
  5. 成功或失敗都會跳訊息，並寫入 log
"""

import argparse
import datetime
import os
import re
import subprocess
import sys
import time

LOG_PATH = os.path.join(
    os.path.expanduser("~"), ".obs_upload_helper.log"
)

ORDER_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{1,39}$")


def log(msg):
    line = "[%s] %s" % (
        datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg
    )
    print(line)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def wait_until_stable(path, timeout=120, interval=1.0, stable_rounds=3):
    """等到檔案大小連續數次不變，確保 OBS 已經寫完。"""
    deadline = time.time() + timeout
    last_size = -1
    same = 0

    while time.time() < deadline:
        if not os.path.exists(path):
            time.sleep(interval)
            continue
        size = os.path.getsize(path)
        if size == last_size and size > 0:
            same += 1
            if same >= stable_rounds:
                return True
        else:
            same = 0
            last_size = size
        time.sleep(interval)

    return os.path.exists(path)


# ---------------------------------------------------------------------------
# macOS: 用 osascript 原生對話框（背景行程也能正常收鍵盤）
# ---------------------------------------------------------------------------

def _osascript_ask_order(filename, size_mb):
    """macOS 用 osascript 彈窗，回傳單號字串或 None（略過）。"""
    info = "%s  (%.1f MB)" % (filename, size_mb)
    script = '''
        set ok to false
        set hint to ""
        repeat while not ok
            try
                set dlg to display dialog ("錄影完成，請輸入出貨單號" & linefeed & linefeed & "%s" & hint) ¬
                    default answer "" with title "出貨測試影片上傳" ¬
                    buttons {"略過", "上傳"} default button "上傳"
            on error number -128
                return "::SKIP::"
            end try
            if button returned of dlg is "略過" then
                return "::SKIP::"
            end if
            set ans to text returned of dlg
            if length of ans < 2 or length of ans > 40 then
                set hint to (linefeed & linefeed & "⚠ 單號需 2~40 字（限英數、_、-）")
            else
                set ok to true
                return ans
            end if
        end repeat
    ''' % info.replace('"', '\\"').replace("\\", "\\\\")

    try:
        proc = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=300,
        )
        if proc.returncode != 0:
            return None
        ans = proc.stdout.strip()
        if ans == "::SKIP::":
            return None
        if ORDER_PATTERN.match(ans):
            return ans
        return None
    except Exception:
        return None


def _osascript_notify(title, message, error=False):
    icon = "stop" if error else "note"
    script = 'display dialog "%s" with title "%s" buttons {"OK"} default button "OK" with icon %s' % (
        message.replace("\\", "\\\\").replace('"', '\\"').replace("\n", '" & linefeed & "'),
        title.replace('"', '\\"'),
        icon,
    )
    try:
        subprocess.run(["osascript", "-e", script],
                        capture_output=True, timeout=60)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Windows / Linux: tkinter
# ---------------------------------------------------------------------------

def _tk_ask_order(filename, size_mb):
    import tkinter as tk
    from tkinter import messagebox

    result = [None]

    root = tk.Tk()
    root.title("出貨測試影片上傳")
    root.attributes("-topmost", True)
    root.resizable(False, False)

    frame = tk.Frame(root, padx=20, pady=16)
    frame.pack(fill="both", expand=True)

    tk.Label(frame, text="錄影完成，請輸入出貨單號",
             font=("", 13, "bold")).pack(anchor="w")
    tk.Label(frame, text="%s  (%.1f MB)" % (filename, size_mb),
             fg="#666").pack(anchor="w", pady=(4, 12))

    entry = tk.Entry(frame, width=32, font=("", 13))
    entry.pack(fill="x")
    entry.focus_force()

    hint = tk.Label(frame, text="", fg="#c00")
    hint.pack(anchor="w", pady=(6, 10))

    def on_ok():
        value = entry.get().strip()
        if not ORDER_PATTERN.match(value):
            hint.config(text="單號格式不符（限英數、_、-，2~40 字）")
            return
        result[0] = value
        root.destroy()

    def on_skip():
        if messagebox.askyesno("確認略過",
                               "略過後影片會留在本機，不會上傳。\n確定略過嗎？",
                               parent=root):
            root.destroy()

    entry.bind("<Return>", lambda _e: on_ok())
    entry.bind("<Escape>", lambda _e: on_skip())

    btns = tk.Frame(frame)
    btns.pack(fill="x")
    tk.Button(btns, text="上傳", width=10, command=on_ok).pack(side="right")
    tk.Button(btns, text="略過", width=10, command=on_skip).pack(
        side="right", padx=(0, 8))

    root.protocol("WM_DELETE_WINDOW", on_skip)
    root.update_idletasks()
    w, h = root.winfo_width(), root.winfo_height()
    x = (root.winfo_screenwidth() - w) // 2
    y = (root.winfo_screenheight() - h) // 3
    root.geometry("+%d+%d" % (x, y))
    root.lift()

    root.mainloop()
    return result[0]


def _tk_notify(title, message, error=False):
    import tkinter as tk
    from tkinter import messagebox
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    root.update_idletasks()
    if error:
        messagebox.showerror(title, message)
    else:
        messagebox.showinfo(title, message)
    root.destroy()


# ---------------------------------------------------------------------------
# 自動選擇平台實作
# ---------------------------------------------------------------------------

def ask_order(filename, size_mb):
    if sys.platform == "darwin":
        return _osascript_ask_order(filename, size_mb)
    return _tk_ask_order(filename, size_mb)


def notify(title, message, error=False):
    if sys.platform == "darwin":
        _osascript_notify(title, message, error)
    else:
        _tk_notify(title, message, error)


# ---------------------------------------------------------------------------
# 上傳邏輯
# ---------------------------------------------------------------------------

def build_remote_name(src_path, order):
    ext = os.path.splitext(src_path)[1] or ".mkv"
    try:
        ts = datetime.datetime.fromtimestamp(os.path.getmtime(src_path))
    except OSError:
        ts = datetime.datetime.now()
    return "%s_%s%s" % (order, ts.strftime("%Y%m%d_%H%M%S"), ext)


def upload(rclone, src, dest, delete_local):
    verb = "moveto" if delete_local else "copyto"
    cmd = [
        rclone, verb, src, dest,
        "--transfers", "1",
        "--retries", "3",
        "--low-level-retries", "10",
        "--stats", "10s",
        "--log-level", "INFO",
    ]
    log("執行：%s" % " ".join(cmd))
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    proc = subprocess.run(
        cmd, capture_output=True, text=True,
        encoding="utf-8", errors="replace", env=env,
    )
    if proc.returncode != 0:
        log("rclone 失敗（exit %d）：%s" % (proc.returncode, proc.stderr.strip()))
        return False, proc.stderr.strip()
    log("上傳完成：%s" % dest)
    return True, ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True, help="錄影檔完整路徑")
    ap.add_argument("--remote", required=True, help="rclone 目的地，例如 gdrive:出貨測試影片")
    ap.add_argument("--rclone", default="rclone", help="rclone 執行檔路徑")
    ap.add_argument("--delete-local", action="store_true", help="上傳成功後刪除本機檔")
    args = ap.parse_args()

    src = args.file
    log("收到錄影檔：%s" % src)

    if not wait_until_stable(src):
        log("檔案不存在或未穩定：%s" % src)
        notify("上傳失敗", "找不到錄影檔或檔案仍在寫入：\n%s" % src, error=True)
        return 1

    size_mb = os.path.getsize(src) / (1024 * 1024)
    order = ask_order(os.path.basename(src), size_mb)

    if order is None:
        log("使用者略過上傳：%s" % src)
        return 0

    remote_name = build_remote_name(src, order)
    dest = "%s/%s" % (args.remote.rstrip("/"), remote_name)

    ok, err = upload(args.rclone, src, dest, args.delete_local)

    if ok:
        notify(
            "上傳完成",
            "單號：%s\n檔名：%s\n位置：%s" % (order, remote_name, args.remote),
        )
        return 0

    notify(
        "上傳失敗",
        "影片已保留在本機：\n%s\n\n錯誤訊息：\n%s\n\n詳細記錄：%s"
        % (src, err[:500], LOG_PATH),
        error=True,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
