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
case "$(uname -s)" in
  Darwin) DIR="${HOME}/DARKIN" ;;
  *)      DIR="/opt/darkin" ;;
esac

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

if [ "$(uname -s)" = "Linux" ]; then
  [ "$(id -u)" -eq 0 ] || die "请用 root 运行（sudo bash $0）—— 需要装系统包和 systemd 服务"
else
  [ "$(id -u)" -ne 0 ] || die "macOS 请不要用 sudo 运行（Homebrew 拒绝 root）；直接 bash $0"
fi

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
GH_BASE="https://github.com/${REPO}/releases/download/${VERSION}"

info "目标：DARKIN ${VERSION} (${os}/${arch})"
info "安装目录：${DIR}"

mkdir -p "$DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 下载（多源回退：自建镜像 → GitHub → 国内加速代理）──────────
# 国内直连 github.com 常被卡；依次尝试。第三方代理仅作通道，
# 完整性以 SHA256 校验为准（校验不过就换源重下）。
DL_URLS=()
[ -n "${DARKIN_DL_BASE:-}" ] && DL_URLS+=("${DARKIN_DL_BASE%/}/${ZIP}")
DL_URLS+=(
  "${GH_BASE}/${ZIP}"
  "https://ghfast.top/${GH_BASE}/${ZIP}"
  "https://gh-proxy.com/${GH_BASE}/${ZIP}"
)
DOWNLOADED=0
for u in "${DL_URLS[@]}"; do
  info "尝试下载：$u"
  rm -f "$TMP/$ZIP"
  if curl -fL --retry 2 --retry-delay 2 --connect-timeout 15 -o "$TMP/$ZIP" "$u"; then
    DOWNLOADED=1; ok "下载完成"; break
  fi
  info "该源不可用，换下一个"
done
[ "$DOWNLOADED" = "1" ] || die "所有下载源均失败。可自行下载 zip 上传服务器后解压（见 README 的离线安装说明），或设置 DARKIN_DL_BASE 指向镜像"

# ── SHA256 校验（尽量从官方源取 SUMS；全部不可达时跳过并提示）──
want=""
for u in "${GH_BASE}/SHA256SUMS" "https://ghfast.top/${GH_BASE}/SHA256SUMS"; do
  if curl -fsSL --retry 1 --connect-timeout 10 -o "$TMP/SHA256SUMS" "$u" 2>/dev/null; then
    want=$(awk -v f="$ZIP" '$2==f {print $1}' "$TMP/SHA256SUMS" | head -1)
    [ -n "${want:-}" ] && break
  fi
done
if [ -n "${want:-}" ]; then
  got=$( (sha256sum "$TMP/$ZIP" 2>/dev/null || shasum -a 256 "$TMP/$ZIP") | awk '{print $1}')
  [ "$want" = "$got" ] || die "SHA256 校验失败（下载损坏或被篡改）：期望 $want 实际 $got"
  ok "SHA256 校验通过"
else
  info "未能获取 SHA256SUMS（网络受限），跳过校验"
fi

# ── 解压 ─────────────────────────────────────────────────────
info "解压到 ${DIR} ..."
unzip -q -o "$TMP/$ZIP" -d "$DIR"
APP="${DIR}/darkin-${VER_NUM}-${os}-${arch}"
[ -d "$APP" ] || APP="$(find "$DIR" -maxdepth 1 -type d -name 'darkin-*' | sort | tail -1)"
[ -d "$APP" ] || die "解压后未找到 darkin-* 目录"

chmod +x "$APP/darkin" "$APP"/*.sh 2>/dev/null || true
ok "已解压：$APP"

# ── 交给安装器 ────────────────────────────────────────────────
cd "$APP"

if [ "$os" = "linux" ]; then
  if [ -f install-deps.sh ]; then
    info "开始安装（依赖 / 数据库 / 访问方式 / 系统服务）..."
    bash install-deps.sh
  else
    ok "安装包已就绪。手动启动：cd $APP && ./start.sh"
  fi
  exit 0
fi

# ── macOS：brew PostgreSQL + config.json + 后台启动 ───────────
if ! command -v psql >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    info "安装 PostgreSQL 16（brew）..."
    brew install postgresql@16
    brew services start postgresql@16
  else
    die "未检测到 psql 和 Homebrew。请先安装 Homebrew（https://brew.sh），再运行：brew install postgresql@16 && brew services start postgresql@16"
  fi
fi
# brew 的 keg-only 版本不在 PATH
export PATH="/opt/homebrew/opt/postgresql@16/bin:/usr/local/opt/postgresql@16/bin:$PATH"

info "等待 PostgreSQL 就绪 ..."
i=0
while ! pg_isready -h 127.0.0.1 -q 2>/dev/null && [ "$i" -lt 30 ]; do
  [ "$i" -eq 0 ] && brew services start postgresql@16 >/dev/null 2>&1 || true
  sleep 1
  i=$((i + 1))
done
pg_isready -h 127.0.0.1 -q || die "PostgreSQL 未就绪，请手动启动：brew services start postgresql@16"

if ! psql -h 127.0.0.1 -d artex -c 'select 1' >/dev/null 2>&1; then
  info "创建数据库 artex ..."
  createdb -h 127.0.0.1 artex || die "createdb artex 失败（用户 $(whoami) 可能无权限）"
fi

if [ ! -f config.json ]; then
  cat > config.json <<JSON
{
  "database": {
    "host": "127.0.0.1",
    "port": 5432,
    "user": "$(whoami)",
    "password": "",
    "dbname": "artex",
    "sslmode": "disable"
  }
}
JSON
  chmod 600 config.json
  ok "已生成 config.json（brew PostgreSQL，用户 $(whoami)）"
fi

chmod +x darkin start.sh stop.sh 2>/dev/null || true
info "后台启动 DARKIN ..."
nohup ./start.sh >> darkin.log 2>&1 &
sleep 3
if curl -fsS -o /dev/null "http://127.0.0.1:8787/api/health" 2>/dev/null; then
  ok "DARKIN 已启动"
else
  warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
  warn "3 秒内未响应，查看日志：tail -50 $APP/darkin.log"
fi

cat <<EOF

DARKIN 已就绪（macOS）：
  访问地址：http://127.0.0.1:8787
  首次打开 → 设置管理员密码 → 粘贴 voucher 激活 → 填 API KEY

  常用操作：
    ./stop.sh             停止
    ./start.sh            前台启动（Ctrl-C 停止）
    tail -f darkin.log    查看日志
EOF
