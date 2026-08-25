#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo " OBS 出貨測試影片自動上傳 — macOS 安裝"
echo "=============================="
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- rclone ----
if command -v rclone &>/dev/null; then
    echo "[✓] rclone 已安裝：$(rclone version | head -1)"
else
    echo "[…] 安裝 rclone …"
    if command -v brew &>/dev/null; then
        brew install rclone
    else
        curl https://rclone.org/install.sh | sudo bash
    fi
    echo "[✓] rclone 安裝完成"
fi
RCLONE_BIN="$(command -v rclone)"

# ---- Python + tkinter ----
# macOS 上用 osascript 所以 tkinter 非必要，但仍需要 python3
PYTHON_BIN=""
for p in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if [ -x "$p" ]; then
        PYTHON_BIN="$p"
        break
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo "[!] 找不到 Python3，請安裝："
    echo "    brew install python@3.11"
    exit 1
fi
echo "[✓] Python：$PYTHON_BIN ($($PYTHON_BIN --version 2>&1))"

# ---- rclone remote ----
echo
if rclone listremotes | grep -q "^gdrive:"; then
    echo "[✓] rclone remote 'gdrive' 已存在"
    echo "    目前設定："
    rclone config show gdrive | grep -E "scope|team_drive" || true
else
    echo "[…] 建立 rclone remote 'gdrive'（會開瀏覽器授權 Google 帳號）"
    echo
    read -rp "是否有 team drive（共用雲端硬碟）？(y/n) " HAS_TEAM
    if [[ "$HAS_TEAM" =~ ^[Yy] ]]; then
        rclone config create gdrive drive scope drive
        echo
        echo "可用的 team drives："
        rclone backend drives gdrive: 2>/dev/null || true
        echo
        read -rp "請貼上 team drive ID：" TEAM_ID
        if [ -n "$TEAM_ID" ]; then
            rclone config update gdrive team_drive "$TEAM_ID"
            echo "[✓] team_drive 已設定"
        fi
    else
        rclone config create gdrive drive scope drive
    fi
fi

# ---- 驗證 ----
echo
echo "[…] 驗證 rclone 連線 …"
if rclone lsd gdrive: --max-depth 1 &>/dev/null; then
    echo "[✓] rclone 連線正常"
else
    echo "[!] rclone 連線失敗，請手動執行 'rclone config' 檢查"
fi

# ---- 印出 OBS 設定 ----
echo
echo "=============================="
echo " 安裝完成！請到 OBS 設定腳本"
echo "=============================="
echo
echo "  OBS → 工具 → 腳本"
echo
echo "  1. Python 設定 頁籤 → Python 路徑："
echo "     若用 Homebrew python3.11："
echo "     /opt/homebrew/opt/python@3.11/Frameworks/Python.framework/Versions/3.11/lib"
echo
echo "  2. 腳本 頁籤 → [+] 加入："
echo "     $SCRIPT_DIR/obs_gdrive_upload.py"
echo
echo "  3. 右側面板填入："
echo "     helper 路徑：$SCRIPT_DIR/upload_helper.py"
echo "     Python 執行檔：$PYTHON_BIN"
echo "     rclone 執行檔：$RCLONE_BIN"
echo "     rclone 目的地：gdrive:你的/目標/路徑"
echo
echo "  4. 先錄 5 秒測試！"
echo
