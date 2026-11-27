#!/usr/bin/env bash
# DARKIN 在线一键安装：下载 → 校验 → 解压 → 安装（依赖 + 数据库 + 系统服务）
#
# 用法（Linux / macOS）：
#   # 交互安装（推荐）：先下载再运行，交互选项在终端可用
#   curl -fLO https://raw.githubusercontent.com/jianmo0x00/darkin-releases/main/install.sh
#   sudo bash install.sh
#
#   # 或管道直跑（脚本会自动把 stdin 重接到终端以支持交互）
#   curl -fsSL https://raw.githubusercontent.com/jianmo0x00/darkin-releases/main/install.sh | sudo bash
#
# 可选参数：
#   --version v0.8.1     指定版本（默认 latest，自动查最新 release）
#   --dir /opt/darkin    安装目录（默认 /opt/darkin）
#
# 环境变量：
#   DARKIN_DL_BASE=https://your-mirror.example.com/darkin   自定义下载源
#   （默认走 GitHub；国内服务器可把 zip 放对象存储后指向它，文件名保持一致）
set -euo pipefail

REPO="jianmo0x00/darkin-releases"
VERSION="latest"
DIR="/opt/darkin"

info() { printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[+]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:?--version 需要参数}"; shift 2 ;;
    --dir)     DIR="${2:?--dir 需要参数}"; shift 2 ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "未知参数：$1（--help 查看用法）" ;;
  esac
done

# 管道执行时 stdin 是脚本内容，交互（安装器选内网/外网）会读不到 —— 重接到终端
if [ ! -t 0 ] && [ -e /dev/tty ]; then
  exec </dev/tty
fi

[ "$(id -u)" -eq 0 ] || die "请用 root 运行（sudo bash $0）—— 需要装系统包和 systemd 服务"

# ── 系统 / 架构 ──────────────────────────────────────────────
case "$(uname -s)" in
  Linux)          os=linux ;;
  Darwin)         os=macos ;;
  *) die "不支持的系统：$(uname -s)。Windows 请直接下载 zip 解压，双击 启动DARKIN.bat" ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) die "不支持的架构：$(uname -m)" ;;
esac

# ── 基础工具 ─────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1; }
if ! need curl; then
  info "安装 curl ..."
  if need apt-get; then apt-get update -qq && apt-get install -y -qq curl
  elif need dnf; then dnf install -y curl
  elif need yum; then yum install -y curl
  else die "请先安装 curl"; fi
fi
if ! need unzip; then
  info "安装 unzip ..."
  if need apt-get; then apt-get install -y -qq unzip
  elif need dnf; then dnf install -y unzip
  elif need yum; then yum install -y unzip
  else die "请先安装 unzip"; fi
fi

# ── 解析版本 ─────────────────────────────────────────────────
if [ "$VERSION" = "latest" ]; then
  info "查询最新版本 ..."
  TAG=$(curl -fsSL --retry 2 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
  [ -n "${TAG:-}" ] || die "无法获取最新版本（GitHub API 不可达），请用 --version v0.8.1 指定"
  VERSION="$TAG"
fi
VER_NUM="${VERSION#v}"

ZIP="darkin-${VER_NUM}-${os}-${arch}.zip"
BASE="${DARKIN_DL_BASE:-https://github.com/${REPO}/releases/download/${VERSION}}"
URL="${BASE}/${ZIP}"

info "目标：DARKIN ${VERSION} (${os}/${arch})"
info "安装目录：${DIR}"
info "下载：${URL}"

mkdir -p "$DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fL --retry 3 --retry-delay 2 -o "$TMP/$ZIP" "$URL" \
  || die "下载失败。国内网络可设置 DARKIN_DL_BASE 指向镜像后重试"

# ── SHA256 校验（Release 里有 SHA256SUMS 才校验）──────────────
if curl -fsSL --retry 2 -o "$TMP/SHA256SUMS" "${BASE}/SHA256SUMS" 2>/dev/null; then
  want=$(awk -v f="$ZIP" '$2==f {print $1}' "$TMP/SHA256SUMS" | head -1)
  if [ -n "${want:-}" ]; then
    got=$( (sha256sum "$TMP/$ZIP" 2>/dev/null || shasum -a 256 "$TMP/$ZIP") | awk '{print $1}')
    [ "$want" = "$got" ] || die "SHA256 校验失败（下载损坏或被篡改）：期望 $want 实际 $got"
    ok "SHA256 校验通过"
  fi
fi

# ── 解压 ─────────────────────────────────────────────────────
info "解压到 ${DIR} ..."
unzip -q -o "$TMP/$ZIP" -d "$DIR"
APP="${DIR}/darkin-${VER_NUM}-${os}-${arch}"
[ -d "$APP" ] || APP="$(find "$DIR" -maxdepth 1 -type d -name 'darkin-*' | sort | tail -1)"
[ -d "$APP" ] || die "解压后未找到 darkin-* 目录"

chmod +x "$APP/darkin" "$APP"/*.sh 2>/dev/null || true
ok "已解压：$APP"

# ── 交给安装器（依赖 + 数据库 + 访问方式 + systemd 启动）──────
if [ -f "$APP/install-deps.sh" ]; then
  info "开始安装（依赖 / 数据库 / 访问方式 / 系统服务）..."
  cd "$APP" && bash install-deps.sh
else
  ok "安装包已就绪。手动启动：cd $APP && ./start.sh"
fi
