# OBS 出貨測試影片自動上傳 — Windows 安裝
# 以系統管理員執行：右鍵 → 以系統管理員身分執行
# 若遇到執行原則限制：Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

$ErrorActionPreference = "Stop"
Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host " OBS 出貨測試影片自動上傳 — Windows 安裝" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- rclone ----
$rcloneBin = Get-Command rclone -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if ($rcloneBin) {
    Write-Host "[OK] rclone 已安裝：$rcloneBin" -ForegroundColor Green
} else {
    Write-Host "[..] 安裝 rclone ..." -ForegroundColor Yellow
    $wingetCheck = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCheck) {
        winget install Rclone.Rclone --accept-package-agreements --accept-source-agreements
    } else {
        Write-Host "[!] 找不到 winget，請手動安裝 rclone：" -ForegroundColor Red
        Write-Host "    https://rclone.org/downloads/" -ForegroundColor Red
        exit 1
    }
    # winget 裝完後 PATH 可能還沒更新
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    $rcloneBin = Get-Command rclone -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $rcloneBin) {
        Write-Host "[!] rclone 安裝後仍找不到，請重開終端機再試" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] rclone 安裝完成" -ForegroundColor Green
}

# ---- Python ----
# OBS for Windows 綁定特定 Python 版本（通常 3.11 64-bit）
$pythonBin = $null
$pythonwBin = $null

# 嘗試常見路徑
$candidates = @(
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
    "C:\Python311\python.exe",
    "C:\Python312\python.exe"
)
foreach ($p in $candidates) {
    if (Test-Path $p) {
        $pythonBin = $p
        break
    }
}

# fallback: PATH 上的 python
if (-not $pythonBin) {
    $pythonBin = Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}
if (-not $pythonBin) {
    $pythonBin = Get-Command python3 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

if (-not $pythonBin) {
    Write-Host "[!] 找不到 Python，請安裝 Python 3.11 (64-bit)：" -ForegroundColor Red
    Write-Host "    https://www.python.org/downloads/" -ForegroundColor Red
    Write-Host "    OBS 腳本頁面會標示所需的 Python 版本" -ForegroundColor Red
    exit 1
}

$pyVer = & $pythonBin --version 2>&1
Write-Host "[OK] Python：$pythonBin ($pyVer)" -ForegroundColor Green

# pythonw.exe（不跳黑色 console 視窗）
$pythonwBin = Join-Path (Split-Path $pythonBin) "pythonw.exe"
if (Test-Path $pythonwBin) {
    Write-Host "[OK] pythonw.exe：$pythonwBin" -ForegroundColor Green
} else {
    $pythonwBin = $pythonBin
    Write-Host "[i]  找不到 pythonw.exe，將使用 python.exe（會有 console 視窗）" -ForegroundColor Yellow
}

# 驗證 tkinter
$tkCheck = & $pythonBin -c "import tkinter; print('ok')" 2>&1
if ($tkCheck -ne "ok") {
    Write-Host "[!] Python 缺少 tkinter，請重新安裝 Python 並勾選 tcl/tk 選項" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] tkinter 正常" -ForegroundColor Green

# ---- rclone remote ----
Write-Host ""
$remotes = rclone listremotes 2>&1
if ($remotes -match "gdrive:") {
    Write-Host "[OK] rclone remote 'gdrive' 已存在" -ForegroundColor Green
} else {
    Write-Host "[..] 建立 rclone remote 'gdrive'（會開瀏覽器授權）" -ForegroundColor Yellow
    $hasTeam = Read-Host "是否有 team drive（共用雲端硬碟）？(y/n)"
    rclone config create gdrive drive scope drive
    if ($hasTeam -match "^[Yy]") {
        Write-Host ""
        Write-Host "可用的 team drives：" -ForegroundColor Cyan
        rclone backend drives gdrive:
        Write-Host ""
        $teamId = Read-Host "請貼上 team drive ID"
        if ($teamId) {
            rclone config update gdrive team_drive $teamId
            Write-Host "[OK] team_drive 已設定" -ForegroundColor Green
        }
    }
}

# ---- 驗證 ----
Write-Host ""
Write-Host "[..] 驗證 rclone 連線 ..." -ForegroundColor Yellow
try {
    rclone lsd gdrive: --max-depth 1 2>&1 | Out-Null
    Write-Host "[OK] rclone 連線正常" -ForegroundColor Green
} catch {
    Write-Host "[!] rclone 連線失敗，請手動執行 'rclone config' 檢查" -ForegroundColor Red
}

# ---- 印出 OBS 設定 ----
Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host " 安裝完成！請到 OBS 設定腳本" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  OBS → 工具 → 腳本"
Write-Host ""
Write-Host "  1. Python 設定 頁籤 → 指到 Python 的安裝資料夾" -ForegroundColor White
Write-Host "     注意：OBS 會標示需要的版本，不符就載不進來" -ForegroundColor Yellow
Write-Host ""
Write-Host "  2. 腳本 頁籤 → [+] 加入：" -ForegroundColor White
Write-Host "     $ScriptDir\obs_gdrive_upload.py" -ForegroundColor White
Write-Host ""
Write-Host "  3. 右側面板填入：" -ForegroundColor White
Write-Host "     helper 路徑：$ScriptDir\upload_helper.py" -ForegroundColor White
Write-Host "     Python 執行檔：$pythonwBin" -ForegroundColor White
Write-Host "     rclone 執行檔：$rcloneBin" -ForegroundColor White
Write-Host "     rclone 目的地：gdrive:你的/目標/路徑" -ForegroundColor White
Write-Host ""
Write-Host "  4. 先錄 5 秒測試！" -ForegroundColor White
Write-Host ""

Read-Host "按 Enter 結束"
