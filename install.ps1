# DARKIN Windows 一键安装：下载 -> 校验 -> 解压 -> 检测 PostgreSQL -> 启动指引
#
# 用法（PowerShell）：
#   # 一行安装（推荐）
#   powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/jianmo0x00/darkin-releases/main/install.ps1 | iex"
#
#   # GitHub 访问不畅时用 jsDelivr 加速
#   powershell -ExecutionPolicy Bypass -c "irm https://cdn.jsdelivr.net/gh/jianmo0x00/darkin-releases@main/install.ps1 | iex"
#
#   # 或下载本文件后带参数运行
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Version v0.8.1 -Dir D:\DARKIN
#
# 环境变量：
#   DARKIN_DL_BASE   自定义下载源（镜像/对象存储），文件名保持一致

param(
    [string]$Version = "latest",
    [string]$Dir = "$env:USERPROFILE\DARKIN"
)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Repo = "jianmo0x00/darkin-releases"

function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

Info "DARKIN Windows 安装器"

# ── 版本 ─────────────────────────────────────────────────────
if ($Version -eq "latest") {
    Info "查询最新版本 ..."
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing -TimeoutSec 20
        $Version = $rel.tag_name
    } catch {
        Die "无法获取最新版本（GitHub API 不可达）。请下载 install.ps1 后用 -Version v0.8.1 指定版本"
    }
}
$VerNum = $Version.TrimStart("v")

$Zip = "darkin-$VerNum-windows-amd64.zip"
$GhBase = "https://github.com/$Repo/releases/download/$Version"

Info "目标：DARKIN $Version (windows/amd64)"
Info "安装目录：$Dir"

# ── 下载（多源回退）──────────────────────────────────────────
$Urls = @()
if ($env:DARKIN_DL_BASE) { $Urls += "$($env:DARKIN_DL_BASE.TrimEnd('/'))/$Zip" }
$Urls += "$GhBase/$Zip"
$Urls += "https://ghfast.top/$GhBase/$Zip"
$Urls += "https://gh-proxy.com/$GhBase/$Zip"

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Tmp = Join-Path $env:TEMP "darkin-install"
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
$ZipPath = Join-Path $Tmp $Zip

$downloaded = $false
foreach ($u in $Urls) {
    Info "尝试下载：$u"
    try {
        Invoke-WebRequest -Uri $u -OutFile $ZipPath -UseBasicParsing -TimeoutSec 600
        $downloaded = $true; Ok "下载完成"; break
    } catch {
        Info "该源不可用，换下一个"
    }
}
if (-not $downloaded) {
    Die "所有下载源均失败。可手动从 Releases 页面下载 zip（或经任意渠道传输），解压后双击 启动DARKIN.bat"
}

# ── SHA256 校验 ──────────────────────────────────────────────
try {
    $sums = (Invoke-WebRequest -Uri "$GhBase/SHA256SUMS" -UseBasicParsing -TimeoutSec 30).Content
    $line = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($Zip) } | Select-Object -First 1)
    if ($line) {
        $want = ($line -split '\s+')[0].ToLower()
        $got = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLower()
        if ($want -ne $got) { Die "SHA256 校验失败（下载损坏或被篡改）：期望 $want 实际 $got" }
        Ok "SHA256 校验通过"
    }
} catch {
    Info "未能获取 SHA256SUMS（网络受限），跳过校验"
}

# ── 解压 ─────────────────────────────────────────────────────
Info "解压到 $Dir ..."
Expand-Archive -Path $ZipPath -DestinationPath $Dir -Force
$AppDir = Join-Path $Dir "darkin-$VerNum-windows-amd64"
if (-not (Test-Path $AppDir)) {
    $cand = Get-ChildItem $Dir -Directory -Filter "darkin-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cand) { $AppDir = $cand.FullName }
}
if (-not (Test-Path $AppDir)) { Die "解压后未找到 darkin-* 目录" }
Ok "已解压：$AppDir"

# ── PostgreSQL 检测 ──────────────────────────────────────────
$pgFound = $null
if (Get-Command psql -ErrorAction SilentlyContinue) {
    $pgFound = "PATH 中的 psql"
} else {
    foreach ($p in @(
        "C:\Program Files\PostgreSQL\18\bin\psql.exe",
        "C:\Program Files\PostgreSQL\17\bin\psql.exe",
        "C:\Program Files\PostgreSQL\16\bin\psql.exe"
    )) {
        if (Test-Path $p) { $pgFound = $p; break }
    }
}
if ($pgFound) {
    Ok "已检测到 PostgreSQL：$pgFound"
} else {
    Warn "未检测到 PostgreSQL（DARKIN 运行必需）"
    Write-Host "    winget 安装：winget install PostgreSQL.PostgreSQL.16"
    Write-Host "    或下载安装包：https://www.postgresql.org/download/windows/"
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            $ans = Read-Host "现在自动安装 PostgreSQL 16？(y/N)"
            if ($ans -match '^[Yy]') {
                winget install --id PostgreSQL.PostgreSQL.16 -e --accept-source-agreements --accept-package-agreements
                Ok "PostgreSQL 安装完成（如提示重启终端，请新开一个窗口）"
            }
        } catch {
            Warn "自动安装失败，请手动安装 PostgreSQL 后再启动 DARKIN"
        }
    }
}

# ── 完成 ─────────────────────────────────────────────────────
Write-Host ""
Ok "DARKIN 已就绪：$AppDir"
Write-Host @"

下一步：
  1. 数据库连接：复制 config.example.json 为 config.json 并填写 PostgreSQL 账号密码
     （默认连 127.0.0.1:5432 的 artex 库；首次启动自动建表）
  2. 双击运行：$AppDir\启动DARKIN.bat
  3. 浏览器打开 http://127.0.0.1:8787
     -> 设置管理员密码 -> 粘贴 voucher 激活 -> 到「API KEY 配置」填模型 Key

说明：Windows 包内已带 Python 3.13 与全部工具（data\tools），无需额外安装。
"@ -ForegroundColor White

try {
    $ans = Read-Host "现在启动 DARKIN？(Y/n)"
    if ($ans -eq "" -or $ans -match '^[Yy]') {
        $launcher = Get-ChildItem $AppDir -Filter "*DARKIN*.bat" | Select-Object -First 1
        if ($launcher) {
            Start-Process -FilePath $launcher.FullName -WorkingDirectory $AppDir
            Ok "已启动，浏览器打开 http://127.0.0.1:8787"
        }
    }
} catch {}

