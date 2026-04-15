# Landscape Mini

[![Latest Release](https://img.shields.io/github/v/release/Cloud370/landscape-mini)](https://github.com/Cloud370/landscape-mini/releases/latest)

[English](docs/en/README.md) | 中文 | [贡献流程](CONTRIBUTING.md) | [**下载最新镜像**](https://github.com/Cloud370/landscape-mini/releases/latest)

Landscape Router 的最小化 x86 镜像构建器。支持 **Debian Trixie** 和 **Alpine Linux** 两种基础系统，可生成精简磁盘镜像（压缩后最小约 76MB），并支持 BIOS + UEFI 双启动。

上游项目：[Landscape Router](https://github.com/ThisSeanZhang/landscape)

## 先看这里

如果你只是想**快速体验 Landscape**：

- 直接去 [Release 页面下载预编译镜像](https://github.com/Cloud370/landscape-mini/releases/latest)

如果你想**做一份自己的镜像**，例如修改：

- LAN / DHCP 网段
- Linux 登录密码
- Web 管理用户名和密码

推荐优先使用：

- [Custom Build 使用说明](docs/zh/custom-build.md)

如果你要开发或调试构建系统本身，再看下面的本地构建说明。

## 特性

- 同时支持 Debian 和 Alpine 两种基础系统
- 镜像体积尽量压小，拿来就能直接跑
- 支持 BIOS + UEFI，常见虚拟化环境都比较友好
- 可以按需带上 Docker
- GitHub Actions 已经接好了，支持自动构建、测试和发布
- fork 用户也可以直接在 GitHub 上跑自定义构建

## 本地开发

如果你已经确定要在本地构建、调试或验证未推送改动，再看这里。

### 本地构建

```bash
# 安装构建依赖（首次）
make deps

# 构建 Debian 镜像
make build

# 构建 Alpine 镜像（更小）
make build-alpine

# 构建含 Docker 的镜像
make build-docker
make build-alpine-docker
```

### 本地测试

```bash
# 自动化 readiness 检查（无需交互）
make deps-test      # 首次需安装测试依赖
make test           # Debian readiness
make test-alpine    # Alpine readiness

# 数据面测试（双 VM：路由器 + 客户端）
make test-dataplane        # Debian dataplane
make test-dataplane-alpine # Alpine dataplane

# 交互式启动（串口控制台）
make test-serial
```

## 部署

### 物理机 / U 盘

```bash
dd if=output/landscape-mini-x86.img of=/dev/sdX bs=4M status=progress
```

### Proxmox VE (PVE)

1. 上传镜像到 PVE 服务器
2. 创建虚拟机（不添加磁盘）
3. 导入磁盘：`qm importdisk <vmid> landscape-mini-x86.img local-lvm`
4. 在 VM 硬件设置中挂载导入的磁盘
5. 设置启动顺序，启动虚拟机

### 云服务器（dd 脚本）

使用 [reinstall](https://github.com/bin456789/reinstall) 脚本将自定义镜像写入云服务器：

```bash
bash <(curl -sL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh) \
    dd --img='https://github.com/Cloud370/landscape-mini/releases/latest/download/landscape-mini-x86.img.gz'
```

> 根分区会在首次启动时自动扩展以填满整个磁盘，无需手动操作。

## 部署后常用操作

### 换源（国内镜像）

部署后如需将软件源切换到国内镜像以加速 `apt` / `apk` 操作，镜像内置了 `setup-mirror.sh` 工具：

```bash
# 查看当前源配置
setup-mirror.sh show

# 一键切换到国内镜像
setup-mirror.sh tuna       # 清华 TUNA
setup-mirror.sh aliyun     # 阿里云
setup-mirror.sh ustc       # 中科大
setup-mirror.sh huawei     # 华为云

# 恢复官方源
setup-mirror.sh reset

# 交互式选择
setup-mirror.sh
```

自动检测 Debian / Alpine 系统，切换后自动执行 `apt update` 或 `apk update`。

## 默认凭据

| 场景 | 用户 | 密码 |
|------|------|------|
| SSH / 系统登录 | `root` | `landscape` |
| SSH / 系统登录 | `ld` | `landscape` |
| 管理网页 | `root` | `root` |

> `custom-build.yml` 支持通过 workflow inputs 或 GitHub Secrets 覆盖 Linux / Web 管理凭据。明文 inputs 适合个人临时使用；如果你更在意安全，优先使用 `CUSTOM_ROOT_PASSWORD`、`CUSTOM_API_USERNAME`、`CUSTOM_API_PASSWORD`。

## 构建配置

编辑 `build.env` 或通过环境变量覆盖：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `APT_MIRROR` | `http://deb.debian.org/debian` | Debian 软件源地址 |
| `ALPINE_MIRROR` | `https://dl-cdn.alpinelinux.org/alpine` | Alpine 软件源地址 |
| `LANDSCAPE_VERSION` | `v0.18.2` | 上游 Landscape 版本号（或指定 tag） |
| `LANDSCAPE_REPO` | `https://github.com/ThisSeanZhang/landscape` | 上游 Landscape 发布仓库 |
| `OUTPUT_FORMAT` | `img` | 输出格式：`img`、`vmdk`、`both` |
| `COMPRESS_OUTPUT` | `yes` | 是否压缩输出镜像 |
| `IMAGE_SIZE_MB` | `2048` | 初始镜像大小（最终会自动缩小） |
| `ROOT_PASSWORD` | `landscape` | root / ld 登录密码 |
| `TIMEZONE` | `Asia/Shanghai` | 时区 |
| `LOCALE` | `en_US.UTF-8` | 系统 locale |

### 自定义构建（GitHub Actions）

仓库提供 `custom-build.yml`，面向 fork 用户提供单变体构建入口，支持：

- `variant`：`default` / `docker` / `alpine` / `alpine-docker`
- `landscape_version`
- `lan_server_ip` / `lan_range_start` / `lan_range_end` / `lan_netmask`
- `root_password`
- `api_username` / `api_password`

当前优先级：**direct inputs > secrets > defaults**。

如果你特别注重安全，推荐把密码类信息放在 GitHub Secrets：
- `CUSTOM_ROOT_PASSWORD`
- `CUSTOM_API_USERNAME`
- `CUSTOM_API_PASSWORD`

workflow 会把**凭据来源信息**按字段写入 `build-metadata.txt`（例如 `api_username_source` / `api_password_source`），同时会记录 `api_username` 的实际值，但不会把密码明文写入 artifact。网络拓扑的有效配置会随 artifact 一起携带为 `effective-landscape_init.toml`，供 `test.yml` 和 release promotion 校验使用。

## 磁盘分区布局

```text
┌──────────────┬────────────┬────────────┬──────────────────────────┐
│ BIOS boot    │ EFI System │ Root (/)   │                          │
│ 1 MiB        │ 200 MiB    │ 剩余空间    │  ← 构建后自动缩小        │
│ (无文件系统) │ FAT32      │ ext4       │                          │
├──────────────┼────────────┼────────────┤                          │
│ GPT: EF02    │ GPT: EF00  │ GPT: 8300  │                          │
└──────────────┴────────────┴────────────┴──────────────────────────┘
```

## 自动化测试

### Readiness 检查

`make test` / `make test-alpine` 执行统一的 router readiness 契约验证：

1. 复制镜像到临时文件（保护构建产物）
2. 后台启动 QEMU（自动检测 KVM）
3. 等待 SSH、API listener、API login、layout 检测完成
4. 验证 `eth0` / `eth1` 以及核心服务进入 running
5. 输出 readiness / service / diagnostics 快照并清理 QEMU

自动适配 systemd（Debian）和 OpenRC（Alpine）两种 init 系统。

### Dataplane 测试

`make test-dataplane` / `make test-dataplane-alpine` 使用双 VM 拓扑验证真实 client-visible dataplane：

```text
Router VM (eth0=WAN/SLIRP, eth1=LAN/mcast) ←→ Client VM (CirrOS, eth0=mcast)
```

测试项：DHCP 分配、Router API 中 lease 可见、Router ↔ Client LAN 连通。

测试日志输出到 `output/test-logs/`。

## QEMU 测试端口

| 服务 | 宿主机端口 | 说明 |
|------|-----------|------|
| SSH | 2222 | `ssh -p 2222 root@localhost` |
| Web UI | 9800 | `http://localhost:9800` |

## CI/CD

- **CI**：手动触发始终可用；对 push 到 `main` / PR，仅在构建相关文件、`.github/` 下相关文件或 `CHANGELOG.md` 变更时自动运行，4 个 variant 通过可复用 workflow 独立构建验证
- **Readiness / E2E 覆盖**：`default`、`alpine` 运行 readiness + dataplane；`docker`、`alpine-docker` 运行 readiness，并显式记录 E2E skipped
- **Artifact contract**：每个 image artifact 都包含 `.img`、`build-metadata.txt`、`effective-landscape_init.toml`
- **Custom Build**：`custom-build.yml` 支持 fork 用户按单 variant 构建，并支持 LAN/DHCP、Linux 密码、Web 管理账号密码输入
- **Manual Retest**：`test.yml` 当前支持按 `run_id` 复测一整组 CI artifacts，并重新传入 SSH / API 凭据；`artifact_suffix` 更适合作为已知 artifact 标识的高级输入，而不是文档承诺的单 artifact 精确复测入口
- **Release**：推送 `v*` tag 时，`release.yml` 仅 promote 同一 commit 上已通过 CI 的 artifact，校验后压缩并创建 GitHub Release

## 许可证

本项目采用 **GPL-3.0** 协议发布，并与上游 [Landscape Router](https://github.com/ThisSeanZhang/landscape) 保持一致。

如果你分发基于本项目构建的镜像或修改版本，请同时留意 GPL-3.0 的相关义务。
