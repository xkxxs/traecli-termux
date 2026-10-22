# traecli-termux

在 **Termux (Android ARM64)** 上安装 TRAE CLI 2.0 的脚本。

> ⚠️ **重要：TRAE CLI 2.0 目前只支持企业 / 团队（ToB）账户。**
> 个人账户即使装好了也无法正常登录和使用（会提示网络异常或鉴权失败）。
> 本项目只是把安装过程记录下来，供有企业账户的人参考，个人用户装了大概率用不上。

---

## 这个脚本解决了什么

TRAE CLI 2.0 官方只声明支持 macOS / Linux / Windows，Termux 不在列表里。
实测它其实能在 Android 上跑，但官方一键安装脚本会失败，原因有三个，脚本逐个处理：

| 组件 | 官方形态 | Termux 上的问题 | 本脚本的做法 |
|---|---|---|---|
| `traecli` 主程序 | `aarch64-unknown-linux-musl` **静态**二进制 | 无，直接能跑 | 原样下载，不做任何 patch |
| `traex-code-mode-host` | glibc 动态链接（`GLIBC_2.17/2.18`） | Termux 没有 glibc；Debian 版 glibc 会被 Android seccomp 杀掉（`set_robust_list` → `rseq` → `clone3` 全是 `SIGSYS`） | 用 [termux-pacman](https://github.com/termux-pacman/glibc-packages) 打过补丁的 glibc，`patchelf` 改 interpreter + rpath |
| `bwrap` 沙箱 | 静态/glibc 版 bubblewrap | Android 禁止非特权 user namespace（`unshare -U` 直接 `EINVAL`），装了也没用 | 放弃沙箱，配置成 `:danger-full-access` |

官方 `install_v2.sh` 具体失败在 **code mode host 的启动 smoke test**：它下载的 host 是 `aarch64-unknown-linux-gnu`（glibc），Termux 里执行会直接 `cannot execute: required file not found`。

另外两个已知问题（脚本无法修复，只能绕过）：

- **自动更新不可用**：`traecli update` 走的是内网域名 `code.byted.org`，公网 DNS 解析不到。升级请重跑安装脚本。
- **没有沙箱 = 全权限**：Android 上拿不到 user namespace，`default_permissions = ":danger-full-access"` 是唯一能用的配置，不要拿它跑不可信仓库。

DNS 不需要特殊处理：虽然是静态 musl，实测在 Termux 下能正常解析（`TRAECLI_HOST=https://example.com` 能真的连到）。不需要像 musl 动态二进制那样去改 `/etc/resolv.conf` 路径。

## 前置要求

- Termux + **aarch64 (ARM64)**
- 约 **1 GB** 可用空间（主程序 486 MB + host 45 MB + glibc 449 MB）
- **企业账户**（个人账户用不了，见顶部说明）

## 安装

```bash
# 推荐：gh-proxy
bash <(curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/xkxxs/traecli-termux/main/install.sh)

# 备选：GitHub 直连
bash <(curl -fsSL https://raw.githubusercontent.com/xkxxs/traecli-termux/main/install.sh)
```

脚本会：

1. 从官方 CDN 拉 `v2/public/stable/latest.json`，按 `linux-aarch64` 取包并校验 sha256
2. 安装主程序到 `$PREFIX/bin/traecli`
3. 如果检测到 `$PREFIX/glibc`，下载 host、用 `patchelf` 指向 glibc 库，装到 `$PREFIX/bin/traex-code-mode-host`
4. 写 `~/.trae/traecli.toml`（关闭沙箱）

想先装 glibc 再跑，或者装完再补 host：

```bash
pkg install -y glibc-repo glibc-runner
bash install.sh            # 重跑即可
TRAECLI_HOST=0 bash install.sh   # 只要主程序，不要 host
```

可用环境变量：

| 变量 | 默认 | 说明 |
|---|---|---|
| `TRAECLI_CHANNEL` | `stable` | 也可 `alpha` |
| `TRAECLI_BIN_DIR` | `$PREFIX/bin` | 安装目录 |
| `TRAECLI_CDN` | 官方 CDN | 自定义下载源 |
| `TRAECLI_HOST` | `1` | 设为 `0` 跳过 code mode host |

## 登录

推荐 PAT（Termux 里复制浏览器链接比较麻烦）：

```bash
export TRAECLI_PERSONAL_ACCESS_TOKEN="<token>"
traecli login --with-trae-pat
```

## 卸载

```bash
rm -f $PREFIX/bin/traecli $PREFIX/bin/traex-code-mode-host
rm -rf ~/.trae ~/.local/share/traecli

# 不再需要 glibc
apt-get purge -y --allow-remove-essential glibc-runner glibc-repo
apt-get purge -y --allow-remove-essential $(dpkg -l | awk '$1=="ii"{print $2}' | grep -E -- "-glibc$|^glibc$")
apt-get autoremove --purge -y
rm -rf $PREFIX/glibc
```

## 实测记录

- 版本：`traecli 0.209.1`（2026-10-10 发布）
- 设备：Termux / Android aarch64 / kernel 4.19
- `traecli --version`、`doctor`、`features list` 正常
- `traex-code-mode-host` 打好 patch 后启动返回 0
- `code_mode` 特性本身默认是 `under development / false`，需要的话自己加 `features.code_mode = true`
- **未验证**：登录后的完整会话（没有企业账户）

如果 code mode 报 `Code Mode is unavailable because ...`，先看 `~/.trae/cli/log/`。

## 说明

- 脚本只从 TRAE 官方 CDN 下载二进制，不改动账号、鉴权和协议。
- TRAE CLI 是字节跳动的商业产品，本项目与官方无关。
- 安装后遇到问题属于使用非官方支持平台的风险，自行承担。
