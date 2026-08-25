#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo " OBS 出貨測試影片自動上傳 — Ubuntu 安裝"
echo "=============================="
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- rclone ----
if command -v rclone &>/dev/null; then
    echo "[✓] rclone 已安裝：$(rclone version | head -1)"
else
    echo "[…] 安裝 rclone …"
    curl https://rclone.org/install.sh | sudo bash
    echo "[✓] rclone 安裝完成"
fi
RCLONE_BIN="$(command -v rclone)"

# ---- Python + tkinter ----
PYTHON_BIN="$(command -v python3 || true)"
if [ -z "$PYTHON_BIN" ]; then
    echo "[…] 安裝 python3 …"
    sudo apt-get update -qq
    sudo apt-get install -y python3 python3-tk
    PYTHON_BIN="$(command -v python3)"
else
    echo "[✓] Python：$PYTHON_BIN ($($PYTHON_BIN --version 2>&1))"
fi

# 檢查 tkinter
if $PYTHON_BIN -c "import tkinter" 2>/dev/null; then
    echo "[✓] tkinter 正常"
else
    echo "[…] 安裝 python3-tk …"
    sudo apt-get update -qq
    sudo apt-get install -y python3-tk
    if $PYTHON_BIN -c "import tkinter" 2>/dev/null; then
        echo "[✓] tkinter 安裝完成"
    else
        echo "[!] tkinter 安裝失敗，請手動執行：sudo apt install python3-tk"
        exit 1
    fi
fi

# ---- rclone remote ----
echo
if rclone listremotes | grep -q "^gdrive:"; then
    echo "[✓] rclone remote 'gdrive' 已存在"
    rclone config show gdrive | grep -E "scope|team_drive" || true
else
    echo "[…] 建立 rclone remote 'gdrive'（會開瀏覽器授權）"
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
echo "  1. Python 設定 頁籤 → Python 路徑"
echo "     通常不需要填，OBS 會自動找到系統的 python3"
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
