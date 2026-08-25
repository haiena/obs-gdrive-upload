# OBS 出貨測試影片自動上傳

機器人出貨前錄製的測試影片，在 OBS 停止錄影後自動跳窗要求輸入單號，
重新命名為 `單號_YYYYMMDD_HHMMSS.副檔名` 後，以 rclone 上傳至 Google Drive。

## 快速安裝

### macOS
```bash
chmod +x setup_macos.sh && ./setup_macos.sh
```

### Windows
雙擊 `setup_windows.bat`，或在 PowerShell 中執行：
```powershell
powershell -ExecutionPolicy Bypass -File setup_windows.ps1
```

### Ubuntu
```bash
chmod +x setup_ubuntu.sh && ./setup_ubuntu.sh
```

安裝腳本會自動處理 rclone、Python、tkinter，並引導設定 Google Drive 授權。
完成後照終端機提示把腳本掛到 OBS 即可。

## 檔案說明

| 檔案 | 角色 |
|---|---|
| `obs_gdrive_upload.py` | OBS 腳本。監聽錄影結束事件，把檔案路徑交給 helper |
| `upload_helper.py` | 獨立行程。等檔案寫完 → 彈窗輸入單號 → rclone 上傳 → 結果通知 |
| `setup_macos.sh` | macOS 一鍵安裝 |
| `setup_windows.bat` / `.ps1` | Windows 一鍵安裝 |
| `setup_ubuntu.sh` | Ubuntu 一鍵安裝 |

### 為什麼拆成兩支

tkinter 直接跑在 OBS 內嵌的 Python 直譯器裡容易卡住 UI 甚至讓 OBS 當掉。
拆開之後 OBS 只做一次 `Popen` 就放行，彈窗與上傳完全在自己的行程裡跑。

`upload_helper.py` 也可以單獨執行來補傳漏掉的檔案：
```bash
python3 upload_helper.py \
  --file "/path/to/video.mkv" \
  --remote "gdrive:出貨測試影片" \
  --rclone /opt/homebrew/bin/rclone \
  --delete-local
```

## 運作流程

```
OBS 停止錄影
   └─ obs_frontend_get_last_recording() 取得路徑
       └─ Popen upload_helper.py（OBS 不等待）
           ├─ 等檔案大小連續 3 次不變（最多 120s）
           ├─ 彈窗輸入單號（可選擇「略過」）
           ├─ 組出 單號_YYYYMMDD_HHMMSS.ext
           │   └─ 時間戳取自檔案 mtime
           ├─ rclone moveto / copyto
           └─ 成功或失敗都跳訊息 + 寫 log
```

- 時間戳用檔案 mtime 而非當下時間，補傳舊檔時才不會標錯日期
- 上傳失敗一律保留本機檔案
- Log：`~/.obs_upload_helper.log`

## 各平台已處理的差異

| 問題 | 平台 | 處理方式 |
|---|---|---|
| `sys.executable` 指向 `obs64.exe` | Windows | `_guess_python()` 偵測並排除，改用 `pythonw.exe` |
| rclone 輸出被 cp950 解碼而亂碼 | Windows | 強制 UTF-8 + `errors="replace"` |
| 多跳一個黑色 console 視窗 | Windows | `CREATE_NO_WINDOW` + `pythonw.exe` |
| 彈窗被壓在 OBS 後面 | macOS | `osascript` 原生對話框（不使用 tkinter） |
| 行程被 OBS 關閉時一起帶走 | Linux / macOS | `start_new_session=True` |

## 疑難排解

| 症狀 | 原因與處置 |
|---|---|
| 錄完完全沒反應 | 檢查 OBS 腳本頁的 log。多半是 helper 路徑沒填或 Python 路徑錯誤 |
| macOS 沒看到彈窗 | 檢查 系統設定 → 隱私權與安全性 → 輔助使用 是否允許 |
| `rclone: command not found` | 從 Finder 開的 OBS 只繼承最小 PATH，rclone 與 Python 一律填**絕對路徑** |
| Windows「remote 不存在」 | 以管理員身分執行時 `%APPDATA%` 指向不同使用者，導致讀不到 `rclone.conf`。改用一般權限，或加 `--config` 指定絕對路徑 |
| 單號輸入被擋 | 預設格式為英數 + `_` + `-`，2~40 字。改 `upload_helper.py` 的 `ORDER_PATTERN` |
| 上傳到一半失敗 | 檔案保留在本機，用 helper 的 CLI 模式補傳即可 |

## 客製化

- **單號規則**：改 `ORDER_PATTERN` 正則
- **檔名格式**：改 `build_remote_name()`
- **改用 API 取單號**：`ask_order()` 與上傳邏輯是分開的，換成 API 查詢即可
- **依日期分資料夾**：在 `build_remote_name()` 回傳值前加上 `ts.strftime("%Y-%m/")`
