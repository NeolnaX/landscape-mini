# Changelog / 变更日志

This file currently tracks unreleased work and recent notable changes.
本文件当前记录未发布改动与近期的重要变更。

## [Unreleased]

### Added / 新增

- Add fork-friendly `custom-build.yml` with high-value topology and credential inputs, plus secrets-preferred guidance for security-sensitive users / 新增面向 fork 用户的 `custom-build.yml`，支持高价值网络与凭据输入，并为注重安全的用户提供 secrets 优先指引

### Changed / 变更

- Rework automatic CI into a faster validation-only surface that checks only the Debian non-Docker raw `img` path, leaving wider output/export combinations to manual or release workflows / 将自动 CI 收缩为更快的验证面，仅校验 Debian 非 Docker 的 raw `img` 路径，把更宽的输出/导出组合留给手动或 release 工作流
- Rebuild Debian Docker / non-Docker release artifacts directly on tag pushes instead of promoting CI artifacts from main, while continuing to publish `.img.gz` + `.ova` release assets / 改为在 tag 推送时直接重建 Debian Docker / 非 Docker 发布产物，而不是从 main 上 promote CI artifacts，同时继续发布 `.img.gz` + `.ova` release 资产
- Rework CI around a reusable single-variant build-and-validate workflow, ship effective topology config inside artifacts, and let tests consume artifact-carried config plus injected credentials / 将 CI 重构为可复用的单变体构建验证流程，把 effective topology 配置随 artifact 一起发布，并让测试使用 artifact 自带配置与注入凭据
- Replace the legacy variant model with an explicit build identity model based on `base_system`, `include_docker`, and `output_formats`, update local build UX, rework tests to consume metadata, and fold `pve-ova` into the normal exporter pipeline / 用 `base_system`、`include_docker`、`output_formats` 替换旧的 variant 模型，更新本地构建体验，让测试改为消费 metadata，并将 `pve-ova` 纳入常规导出流水线
- Rewrite CI, Custom Build, retest, release promotion, and repository docs around tuple-based build identities instead of named variants / 将 CI、Custom Build、复测、release promotion 与仓库文档统一重写为基于 tuple 的构建身份模型，不再围绕命名 variant 运转

### Fixed / 修复

- Switch image default DNS resolver to `1.1.1.1` while keeping build-time DNS aligned with the active build environment, so CI stays resilient without breaking resumed/offline-friendly workflows / 将镜像默认 DNS 解析器切换为 `1.1.1.1`，同时让构建阶段 DNS 跟随当前构建环境，既增强 CI 稳定性，又避免破坏恢复构建/离线友好流程
- Add multi-source probing and early-fail mirror resolution so local builds and GitHub CI can select healthy package sources automatically when explicit mirrors are not set, while preserving `--skip-to` source provenance on resumed builds and preferring representative download throughput over raw latency / 新增多源探测与早失败镜像源解析逻辑，使本地构建与 GitHub CI 在未显式指定镜像源时可自动选择健康可用的软件源，在恢复构建时保留 `--skip-to` 的源 provenance，并优先参考代表性下载吞吐而非仅看延迟
- Let CI inherit configurable Docker mirror settings while making chroot retry steps fail fast on command errors / 让 CI 继承可配置的 Docker 镜像源设置，并让 chroot 重试步骤在命令失败时立即终止
- Add configurable Debian Docker source settings and retry transient package/network operations during image builds to reduce CI failures from upstream mirror instability / 为 Debian Docker 构建增加可配置的软件源设置，并对镜像构建中的易失败网络/包管理步骤增加重试，降低上游源抖动导致的 CI 失败
- Retry Debian and Alpine Docker package installation steps during image builds so transient upstream network failures are less likely to fail CI / 在镜像构建期间为 Debian 和 Alpine 的 Docker 安装步骤增加重试，降低上游网络瞬时故障导致 CI 失败的概率
- Use `C.UTF-8` as the default image locale so Debian and Alpine shells no longer warn about missing `en_US.UTF-8` locale data on first boot / 将镜像默认 locale 改为 `C.UTF-8`，避免 Debian 和 Alpine 首次启动时因缺少 `en_US.UTF-8` locale 数据而出现 shell 警告
- Stop hardcoding test SSH/API credentials so custom builds and retests can validate non-default passwords consistently / 移除测试中对 SSH/API 凭据的硬编码，使自定义构建与复测能够稳定验证非默认密码

## [0.2.6] - 2026-04-14

### Fixed / 修复

- Publish only release image archives and stop uploading duplicate metadata files as GitHub release assets / 发布时仅上传镜像压缩包，不再将重复的 metadata 文件作为 GitHub release 资产上传

## [0.2.5] - 2026-04-14

### Fixed / 修复

- Fix tagged release builds to keep using the upstream Landscape version from `build.env`, harden asset downloads, and make manual retest workflows restore build metadata from the correct path / 修复 tag 发布时错误使用仓库版本号替代上游 Landscape 版本的问题，加固资源下载校验，并修正手动复测 workflow 的 build metadata 路径

## [0.2.4] - 2026-04-14

### Changed / 变更

- Rebuild validation around separate readiness and dataplane suites, and align CI / manual retest / release workflows on a shared validation contract with traceable artifact identity / 将验证体系重构为 readiness 与 dataplane 两套测试，并统一 CI / 手动复测 / release 的验证契约与可追踪 artifact 身份

### Fixed / 修复

- Harden CI and release test stability by retrying API login, using less brittle tool detection, and aligning CI's default Landscape version with release builds / 通过重试 API 登录、改进工具探测稳定性，并让 CI 默认 Landscape 版本与 release 保持一致，提升 CI 与发布测试稳定性

## [0.2.3] - 2026-04-14

### Changed / 变更

- Sync with upstream Landscape v0.18.2 / 同步上游 Landscape v0.18.2

### Fixed / 修复

- Improve build and test reliability to reduce false positives and stuck CI runs / 改进构建与测试可靠性，减少误报和卡死的 CI 任务
- Validate CI on pull requests to `main` and make workflow conditions safer / 对发往 `main` 的 Pull Request 执行 CI 校验，并增强工作流条件判断的安全性
- Relax Web UI and API readiness checks to better match runtime startup behavior / 放宽 Web UI 与 API 就绪探测，使其更贴近实际启动行为
- Wait for Landscape API readiness before failing health checks, especially for Alpine Docker startup lag / 在健康检查失败前等待 Landscape API 就绪，降低 Alpine Docker 启动较慢导致的误判

## [0.2.2] - 2026-02-23

### Changed / 变更

- Sync with upstream Landscape v0.13.0 (add device mark) / 同步上游 Landscape v0.13.0（新增设备标记功能）

## [0.2.1] - 2026-02-13

### Added / 新增

- Add bilingual CHANGELOG.md following Keep a Changelog format / 新增双语变更日志，遵循 Keep a Changelog 规范 (`e72d334`)
- Add `setup-mirror.sh` script for switching to Chinese package mirrors / 新增 `setup-mirror.sh` 脚本，用于切换国内软件包镜像源 (`cf40c6c`)

### Changed / 变更

- Update image size to ~76MB, add CI concurrency control / 更新镜像大小至约 76MB，增加 CI 并发控制 (`5f0abf9`)

### Fixed / 修复

- Improve kernel module trimming for stability and compatibility / 改进内核模块裁剪策略，提升稳定性和兼容性 (`f623ca0`)
- Add VMware/ESXi storage drivers to Alpine initramfs / 为 Alpine initramfs 添加 VMware/ESXi 存储驱动 (`ff8315f`)
- Use kernel `modules=` param for ESXi storage drivers instead of custom mkinitfs feature / 使用内核 `modules=` 参数加载 ESXi 存储驱动，替代自定义 mkinitfs 特性 (`4b5551b`)

## [0.2.0] - 2026-02-12

### Added / 新增

- Add Alpine Linux support as alternative base system / 新增 Alpine Linux 作为可选基础系统 (`44165b9`)
- Add end-to-end network tests (DHCP, DNS, NAT) / 新增端到端网络测试（DHCP、DNS、NAT） (`44165b9`)

### Changed / 变更

- Optimize CI pipeline with parallel build-and-test jobs / 优化 CI 流水线，采用并行构建与测试 (`44165b9`)
- Sync documentation with new architecture / 同步文档以反映新架构 (`44165b9`)

### Fixed / 修复

- Fix output directory permissions and disable fail-fast in CI / 修复 CI 中输出目录权限问题并禁用 fail-fast (`ee0cf7e`)
- Fix `work/` directory permissions for E2E CirrOS download / 修复 E2E 测试中 CirrOS 下载的 `work/` 目录权限 (`3965b5a`)
- Switch CirrOS mirror to GitHub and validate download result / 将 CirrOS 镜像源切换至 GitHub 并校验下载结果 (`3ac6bf9`)
- Update `test.yml` fallback workflow reference from `build.yml` to `ci.yml` / 更新 `test.yml` 中回退工作流引用，由 `build.yml` 改为 `ci.yml` (`5e01a05`)

## [0.1.2] - 2026-02-11

### Added / 新增

- Add auto-expand root partition on first boot / 新增首次启动时自动扩展根分区 (`72b089f`)
- Add deployment documentation / 新增部署文档 (`72b089f`)

### Fixed / 修复

- Fix VNC display configuration / 修复 VNC 显示配置 (`72b089f`)
- Use latest release URL instead of VERSION placeholder in docs / 文档中使用最新版本链接替代 VERSION 占位符 (`71d0e01`)

## [0.1.1] - 2026-02-11

### Changed / 变更

- Aggressive image size reduction from 693MB to 312MB / 大幅压缩镜像体积，从 693MB 缩减至 312MB (`b2dc2a8`)

## [0.1.0] - 2026-02-11

### Added / 新增

- Add minimal x86 image builder using debootstrap / 新增基于 debootstrap 的最小化 x86 镜像构建工具 (`0112655`)
- Support BIOS + UEFI dual boot for PVE/SeaBIOS compatibility / 支持 BIOS + UEFI 双引导，兼容 PVE/SeaBIOS (`822b5e0`)
- Add non-interactive automated test system / 新增非交互式自动化测试系统 (`e6698f7`)
- Make test non-interactive by default, add README and CI test jobs / 测试默认为非交互模式，新增 README 和 CI 测试任务 (`41c415f`)

### Changed / 变更

- Improve build and CI pipeline / 改进构建和 CI 流水线 (`f34c5df`)
- Split CI into `ci.yml` and `release.yml` / 将 CI 拆分为 `ci.yml` 和 `release.yml` (`d260ab9`)

### Fixed / 修复

- Use default mirror in CI and split artifacts by format / CI 中使用默认镜像源并按格式拆分构建产物 (`621bceb`)
- Respect `APT_MIRROR` env var override in `build.env` / `build.env` 中正确读取 `APT_MIRROR` 环境变量覆盖值 (`e261fbb`)
- Remove redundant `.gz` artifacts, compress only for release / 移除冗余 `.gz` 产物，仅在发布时压缩 (`74d9887`)
- Add tags trigger to enable release on version tags / 添加标签触发器以支持版本标签发布 (`bffc1f2`)
- Add concurrency group to prevent duplicate CI runs / 添加并发组以防止 CI 重复运行 (`ee11fe2`)
- Add contents write permission for release job / 为发布任务添加内容写入权限 (`97b6240`)

[Unreleased]: https://github.com/Cloud370/landscape-mini/compare/v0.2.6...HEAD
[0.2.6]: https://github.com/Cloud370/landscape-mini/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/Cloud370/landscape-mini/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/Cloud370/landscape-mini/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/Cloud370/landscape-mini/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/Cloud370/landscape-mini/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/Cloud370/landscape-mini/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Cloud370/landscape-mini/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/Cloud370/landscape-mini/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Cloud370/landscape-mini/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Cloud370/landscape-mini/releases/tag/v0.1.0
