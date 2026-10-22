#!/data/data/com.termux/files/usr/bin/bash
# TRAE CLI 2.0 for Termux (aarch64)
#   - 主程序: 官方 aarch64 musl 静态二进制，直接可用
#   - code mode host: glibc 动态链接，用 glibc-runner 装的 glibc 库 + patchelf 修好
# 用法: bash traecli-termux-install.sh
# 可选环境变量:
#   TRAECLI_CHANNEL=stable|alpha      默认 stable
#   TRAECLI_BIN_DIR=/path             默认 $PREFIX/bin
#   TRAECLI_CDN=https://...           默认官方 CDN
#   TRAECLI_HOST=0                    不装 code mode host
set -euo pipefail

BASE="${TRAECLI_CDN:-https://lf-cdn.trae.com.cn/obj/trae-com-cn/trae-cli}"
CHANNEL="${TRAECLI_CHANNEL:-stable}"
PLATFORM="linux-aarch64"
BIN_DIR="${TRAECLI_BIN_DIR:-$PREFIX/bin}"
CONF_DIR="${TRAE_HOME:-$HOME/.trae}"
CONF="$CONF_DIR/traecli.toml"
GLIBC_DIR="${GLIBC_PREFIX:-$PREFIX/glibc}"
WANT_HOST="${TRAECLI_HOST:-1}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Linux" ] || die "只支持 Linux/Android"
[ "$(uname -m)" = "aarch64" ] || die "只支持 aarch64（当前 $(uname -m)）"
command -v curl >/dev/null || die "缺少 curl：pkg install curl"
command -v gunzip >/dev/null || die "缺少 gunzip：pkg install gzip"

say "获取 $CHANNEL 最新版本信息"
meta=$(curl -fsSL --retry 3 --connect-timeout 15 "$BASE/v2/public/$CHANNEL/latest.json") \
  || die "拉取版本信息失败"

version=$(printf '%s\n' "$meta" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$version" ] || die "解析 version 失败"

# 从 pretty-printed manifest 里按 filename 取 url/sha256/size
pick() { # pick <filename> <field>
    printf '%s\n' "$meta" | grep -A3 "\"filename\": \"$1\"" | head -4 \
        | sed -n "s/.*\"$2\": *\"\{0,1\}\([^\",]*\)\"\{0,1\}.*/\1/p" | head -1
}
art="traex-$PLATFORM.gz"
url=$(pick "$art" url)
sha=$(pick "$art" sha256)
[ -n "$url" ] || die "没有找到 $PLATFORM 的发布包"
say "版本 $version"

tmp=$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/traecli.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fetch() { # fetch <url> <out> <sha>
    curl -fL --retry 3 --connect-timeout 15 -o "$2" "$1" || die "下载失败: $1"
    if [ -n "$3" ] && command -v sha256sum >/dev/null; then
        actual=$(sha256sum "$2" | awk '{print $1}')
        [ "$actual" = "$3" ] || die "sha256 校验失败: $2"
    fi
}

say "下载主程序（约 170 MB，解压后约 500 MB）"
fetch "$url" "$tmp/traex.gz" "$sha"
gunzip -c "$tmp/traex.gz" > "$tmp/traecli"
chmod 0755 "$tmp/traecli"
"$tmp/traecli" --version >/dev/null 2>&1 || die "主程序无法运行"

mkdir -p "$BIN_DIR"
mv -f "$tmp/traecli" "$BIN_DIR/traecli"
say "已安装 $BIN_DIR/traecli  ($("$BIN_DIR/traecli" --version 2>/dev/null | head -1))"

# ---- code mode host ----
HOST_OK=0
if [ "$WANT_HOST" = "1" ]; then
    if [ ! -f "$GLIBC_DIR/lib/ld-linux-aarch64.so.1" ]; then
        say "跳过 code mode host：没有 $GLIBC_DIR"
        say "  需要的话先执行: pkg install -y glibc-repo glibc-runner 然后重跑本脚本"
    else
        command -v patchelf >/dev/null || pkg install -y patchelf >/dev/null
        hostart="traex-code-mode-host-$PLATFORM.gz"
        hurl=$(pick "$hostart" url)
        hsha=$(pick "$hostart" sha256)
        if [ -z "$hurl" ]; then
            say "跳过 code mode host：manifest 里没有 $hostart"
        else
            say "下载 code mode host"
            fetch "$hurl" "$tmp/host.gz" "$hsha"
            gunzip -c "$tmp/host.gz" > "$tmp/host"
            chmod 0755 "$tmp/host"
            # 官方是按 glibc 编译的，这里把 interpreter 和 rpath 指到 glibc-runner 的库
            patchelf --set-rpath "$GLIBC_DIR/lib" \
                     --set-interpreter "$GLIBC_DIR/lib/ld-linux-aarch64.so.1" \
                     "$tmp/host" || die "patchelf 处理 host 失败"
            "$tmp/host" </dev/null >/dev/null 2>&1 || die "code mode host 启动失败"
            mv -f "$tmp/host" "$BIN_DIR/traex-code-mode-host"
            HOST_OK=1
            say "已安装 $BIN_DIR/traex-code-mode-host（glibc: $GLIBC_DIR）"
        fi
    fi
fi

# Android 上无法运行 bwrap（内核禁止非特权 user namespace），只能全权限直跑
if [ ! -f "$CONF" ]; then
    mkdir -p "$CONF_DIR"
    cat > "$CONF" <<'EOF'
# TRAE CLI on Termux
# Android 的 seccomp 禁止非特权 user namespace，bwrap 沙箱无法使用，只能关闭沙箱。
default_permissions = ":danger-full-access"
approval_policy = "on-request"
EOF
    say "已写入 $CONF（关闭沙箱）"
else
    grep -q '^default_permissions' "$CONF" || say "注意：$CONF 里没有 default_permissions，建议设为 \":danger-full-access\""
fi

if [ "$HOST_OK" = "1" ]; then
    hostmsg="code mode host 已安装。code_mode 特性默认是 under development/false，"
    hostmsg="$hostmsg需要的话在 $CONF 加一句 features.code_mode = true 再试。"
else
    hostmsg="没有 code mode host，code mode 工具不可用；shell / 编辑 / MCP 不受影响。"
fi

cat <<EOF

完成。下一步：

  1) 登录（PAT 方式，Termux 里比浏览器 OAuth 省事）：
       export TRAECLI_PERSONAL_ACCESS_TOKEN="<你的 token>"
       traecli login --with-trae-pat

  2) 启动：
       cd ~/你的项目 && traecli

$hostmsg

沙箱：bwrap 在 Android 上用不了（非特权 user namespace 被禁），已配置成 Full Access。
自动更新：更新源指向内网域名，会失败；升级请重跑本脚本。

卸载：
  rm -f "$BIN_DIR/traecli" "$BIN_DIR/traex-code-mode-host" "$CONF"
  pkg uninstall glibc-runner glibc-repo   # 如果不再需要 glibc
EOF
