"""
OBS Studio 腳本：錄影結束後彈窗輸入單號，並以 rclone 上傳至 Google Drive。

安裝方式：
  OBS -> 工具(Tools) -> 腳本(Scripts) -> Python 設定 頁籤設定 Python 路徑
  -> 腳本 頁籤 -> [+] 加入本檔案

注意：本腳本不會自己開視窗，而是把工作丟給 upload_helper.py 這支獨立程式，
避免 tkinter 在 OBS 內嵌 Python 直譯器裡造成當機或卡住 UI。
"""

import os
import sys
import subprocess

import obspython as obs

# ---- 預設值（可在 OBS 腳本面板上調整） ----
HELPER_PATH = ""        # upload_helper.py 的完整路徑


def _guess_python():
    """OBS 內嵌直譯器在 Windows 上 sys.executable 會指到 obs64.exe，必須排除。"""
    exe = sys.executable or ""
    base = os.path.basename(exe).lower()
    if base.startswith("python"):
        # Windows 優先用 pythonw.exe，才不會多跳一個黑色 console 視窗
        if os.name == "nt":
            cand = os.path.join(os.path.dirname(exe), "pythonw.exe")
            if os.path.isfile(cand):
                return cand
        return exe
    return "pythonw.exe" if os.name == "nt" else "python3"


PYTHON_BIN = _guess_python()
RCLONE_BIN = "rclone"
REMOTE = "gdrive:出貨測試影片"
DELETE_LOCAL = True
ENABLED = True


def script_description():
    return (
        "<b>出貨測試影片自動上傳</b><br>"
        "錄影結束後會跳出視窗要求輸入單號，"
        "檔名格式為 <code>單號_YYYYMMDD_HHMMSS.副檔名</code>，"
        "接著以 rclone 上傳至指定的 Google Drive 路徑。"
    )


def script_properties():
    props = obs.obs_properties_create()

    obs.obs_properties_add_bool(props, "enabled", "啟用自動上傳")
    obs.obs_properties_add_path(
        props, "helper_path", "upload_helper.py 路徑",
        obs.OBS_PATH_FILE, "Python (*.py)", None
    )
    obs.obs_properties_add_path(
        props, "python_bin", "Python 執行檔",
        obs.OBS_PATH_FILE, None, None
    )
    obs.obs_properties_add_path(
        props, "rclone_bin", "rclone 執行檔",
        obs.OBS_PATH_FILE, None, None
    )
    obs.obs_properties_add_text(
        props, "remote", "rclone 目的地 (remote:path)", obs.OBS_TEXT_DEFAULT
    )
    obs.obs_properties_add_bool(props, "delete_local", "上傳成功後刪除本機檔案")

    return props


def script_defaults(settings):
    obs.obs_data_set_default_bool(settings, "enabled", True)
    obs.obs_data_set_default_string(settings, "python_bin", _guess_python())
    obs.obs_data_set_default_string(settings, "rclone_bin", "rclone")
    obs.obs_data_set_default_string(settings, "remote", "gdrive:出貨測試影片")
    obs.obs_data_set_default_bool(settings, "delete_local", True)


def script_update(settings):
    global HELPER_PATH, PYTHON_BIN, RCLONE_BIN, REMOTE, DELETE_LOCAL, ENABLED

    ENABLED = obs.obs_data_get_bool(settings, "enabled")
    HELPER_PATH = obs.obs_data_get_string(settings, "helper_path")
    PYTHON_BIN = obs.obs_data_get_string(settings, "python_bin") or "python3"
    RCLONE_BIN = obs.obs_data_get_string(settings, "rclone_bin") or "rclone"
    REMOTE = obs.obs_data_get_string(settings, "remote")
    DELETE_LOCAL = obs.obs_data_get_bool(settings, "delete_local")


def script_load(settings):
    obs.obs_frontend_add_event_callback(on_event)


def script_unload():
    obs.obs_frontend_remove_event_callback(on_event)


def on_event(event):
    if event != obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED:
        return
    if not ENABLED:
        return

    path = obs.obs_frontend_get_last_recording()
    if not path:
        obs.script_log(obs.LOG_WARNING, "取不到最後一次錄影的檔案路徑，略過上傳。")
        return

    if not HELPER_PATH or not os.path.isfile(HELPER_PATH):
        obs.script_log(obs.LOG_ERROR,
                       "尚未設定 upload_helper.py 路徑，無法上傳：%s" % HELPER_PATH)
        return

    cmd = [
        PYTHON_BIN, HELPER_PATH,
        "--file", path,
        "--remote", REMOTE,
        "--rclone", RCLONE_BIN,
    ]
    if DELETE_LOCAL:
        cmd.append("--delete-local")

    try:
        kwargs = {}
        if os.name == "nt":
            kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
        else:
            kwargs["start_new_session"] = True
        subprocess.Popen(cmd, **kwargs)
        obs.script_log(obs.LOG_INFO, "已交付上傳程序：%s" % path)
    except Exception as exc:
        obs.script_log(obs.LOG_ERROR, "啟動上傳程序失敗：%s" % exc)
