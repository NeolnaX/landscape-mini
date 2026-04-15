# Landscape Mini

[![Latest Release](https://img.shields.io/github/v/release/Cloud370/landscape-mini)](https://github.com/Cloud370/landscape-mini/releases/latest)

English | [中文](../../README.md) | [Contributing](../../CONTRIBUTING.md) | [Download Latest Image](https://github.com/Cloud370/landscape-mini/releases/latest)

A minimal x86 image builder for Landscape Router. It supports both **Debian Trixie** and **Alpine Linux** as base systems, produces compact disk images (as small as ~76 MB when compressed), and supports dual BIOS + UEFI boot.

Upstream project: [Landscape Router](https://github.com/ThisSeanZhang/landscape)

## Start Here

If you just want to **try Landscape quickly**:

- Download a prebuilt image from the [latest release](https://github.com/Cloud370/landscape-mini/releases/latest)

If you want to **build a customized image**, for example to change:

- LAN / DHCP subnet settings
- Linux login password
- Web management username and password

Start with:

- [Custom Build Guide](./custom-build.md)

If you are developing or debugging the build system itself, continue with the local build instructions below.

## Features

- Supports both Debian and Alpine as base systems
- Optimized for minimal image size while remaining ready to boot and use
- Supports both BIOS and UEFI for broad virtualization compatibility
- Optional Docker support
- GitHub Actions workflows are already set up for automated build, test, and release
- Fork users can run customized builds directly on GitHub

## Local Development

If you plan to build locally, debug issues, or validate changes before pushing them, start here.

### Local Build

```bash
# Install build dependencies (first time only)
make deps

# Build Debian image
make build

# Build Alpine image (smaller)
make build-alpine

# Build images with Docker included
make build-docker
make build-alpine-docker
```

### Local Test

```bash
# Automated readiness checks (non-interactive)
make deps-test      # Install test dependencies first
make test           # Debian readiness
make test-alpine    # Alpine readiness

# Dataplane tests (two VMs: router + client)
make test-dataplane        # Debian dataplane
make test-dataplane-alpine # Alpine dataplane

# Interactive boot (serial console)
make test-serial
```

## Deployment

### Physical Machine / USB Drive

```bash
dd if=output/landscape-mini-x86.img of=/dev/sdX bs=4M status=progress
```

### Proxmox VE (PVE)

1. Upload the image to the PVE host.
2. Create a VM without attaching a disk.
3. Import the disk: `qm importdisk <vmid> landscape-mini-x86.img local-lvm`
4. Attach the imported disk in the VM hardware settings.
5. Set the boot order and start the VM.

### Cloud Server (dd Script)

Use the [reinstall](https://github.com/bin456789/reinstall) script to write the custom image onto a cloud server:

```bash
bash <(curl -sL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh) \
    dd --img='https://github.com/Cloud370/landscape-mini/releases/latest/download/landscape-mini-x86.img.gz'
```

> The root partition automatically expands on first boot to fill the entire disk. No manual intervention is required.

## Common Post-Deployment Operations

### Switch Package Mirrors

If you want to switch to a closer or faster package mirror after deployment for `apt` or `apk`, the image includes the `setup-mirror.sh` utility:

```bash
# Show current mirror configuration
setup-mirror.sh show

# Switch mirrors with one command
setup-mirror.sh tuna       # Tsinghua TUNA
setup-mirror.sh aliyun     # Alibaba Cloud
setup-mirror.sh ustc       # USTC
setup-mirror.sh huawei     # Huawei Cloud

# Restore official upstream mirrors
setup-mirror.sh reset

# Interactive selection
setup-mirror.sh
```

The script automatically detects Debian vs. Alpine and runs `apt update` or `apk update` after switching.

## Default Credentials

| Scenario | Username | Password |
|------|------|------|
| SSH / system login | `root` | `landscape` |
| SSH / system login | `ld` | `landscape` |
| Web UI | `root` | `root` |

> `custom-build.yml` can override Linux and Web UI credentials through workflow inputs or GitHub Secrets. Plaintext inputs are fine for temporary personal use; if security matters, prefer `CUSTOM_ROOT_PASSWORD`, `CUSTOM_API_USERNAME`, and `CUSTOM_API_PASSWORD`.

## Build Configuration

Edit `build.env` or override values with environment variables:

| Variable | Default | Description |
|------|--------|------|
| `APT_MIRROR` | `http://deb.debian.org/debian` | Debian package mirror URL |
| `ALPINE_MIRROR` | `https://dl-cdn.alpinelinux.org/alpine` | Alpine package mirror URL |
| `LANDSCAPE_VERSION` | `v0.18.2` | Upstream Landscape version (or specific tag) |
| `LANDSCAPE_REPO` | `https://github.com/ThisSeanZhang/landscape` | Upstream Landscape release repository |
| `OUTPUT_FORMAT` | `img` | Output format: `img`, `vmdk`, or `both` |
| `COMPRESS_OUTPUT` | `yes` | Whether to compress output images |
| `IMAGE_SIZE_MB` | `2048` | Initial image size (automatically shrunk later) |
| `ROOT_PASSWORD` | `landscape` | Login password for `root` / `ld` |
| `TIMEZONE` | `Asia/Shanghai` | Time zone |
| `LOCALE` | `en_US.UTF-8` | System locale |

### Custom Builds (GitHub Actions)

The repository provides `custom-build.yml` as a single-variant build entry point for fork users. It supports:

- `variant`: `default` / `docker` / `alpine` / `alpine-docker`
- `landscape_version`
- `lan_server_ip` / `lan_range_start` / `lan_range_end` / `lan_netmask`
- `root_password`
- `api_username` / `api_password`

Current precedence: **direct inputs > secrets > defaults**.

If you care about credential hygiene, store password-related values in GitHub Secrets:
- `CUSTOM_ROOT_PASSWORD`
- `CUSTOM_API_USERNAME`
- `CUSTOM_API_PASSWORD`

The workflow records the **credential source** for each field in `build-metadata.txt` (for example, `api_username_source` and `api_password_source`). It also records the actual `api_username` value, but never writes plaintext passwords into artifacts. The effective network topology is bundled as `effective-landscape_init.toml` so `test.yml` and release promotion can validate it.

## Disk Partition Layout

```text
┌──────────────┬────────────┬────────────┬──────────────────────────┐
│ BIOS boot    │ EFI System │ Root (/)   │                          │
│ 1 MiB        │ 200 MiB    │ remaining  │  ← automatically shrunk  │
│ (no fs)      │ FAT32      │ ext4       │     after build          │
├──────────────┼────────────┼────────────┤                          │
│ GPT: EF02    │ GPT: EF00  │ GPT: 8300  │                          │
└──────────────┴────────────┴────────────┴──────────────────────────┘
```

## Automated Testing

### Readiness Checks

`make test` / `make test-alpine` run the shared router readiness contract:

1. Copy the image to a temporary file to protect build artifacts.
2. Start QEMU in the background with automatic KVM detection.
3. Wait for SSH, API listener, API login, and layout detection.
4. Verify `eth0` / `eth1` and ensure core services reach the running state.
5. Output readiness, service, and diagnostics snapshots, then clean up QEMU.

The test runner automatically adapts to both init systems: systemd (Debian) and OpenRC (Alpine).

### Dataplane Tests

`make test-dataplane` / `make test-dataplane-alpine` validate real client-visible dataplane behavior with a two-VM topology:

```text
Router VM (eth0=WAN/SLIRP, eth1=LAN/mcast) ←→ Client VM (CirrOS, eth0=mcast)
```

Coverage includes DHCP lease assignment, lease visibility in the Router API, and LAN connectivity between the router and client.

Test logs are written to `output/test-logs/`.

## QEMU Test Ports

| Service | Host Port | Description |
|------|-----------|------|
| SSH | 2222 | `ssh -p 2222 root@localhost` |
| Web UI | 9800 | `http://localhost:9800` |

## CI/CD

- **CI**: Manual runs are always available. On pushes to `main` and on pull requests, workflows run automatically only when build-related files, relevant files under `.github/`, or `CHANGELOG.md` change. All 4 variants are built and validated independently through reusable workflows.
- **Readiness / E2E coverage**: `default` and `alpine` run readiness + dataplane tests; `docker` and `alpine-docker` run readiness only and explicitly record E2E as skipped.
- **Artifact contract**: Every image artifact includes `.img`, `build-metadata.txt`, and `effective-landscape_init.toml`.
- **Custom Build**: `custom-build.yml` allows fork users to build a single variant with custom LAN/DHCP settings, Linux password, and Web UI credentials.
- **Manual Retest**: `test.yml` currently supports retesting a full set of CI artifacts by `run_id`, with SSH / API credentials passed in again. `artifact_suffix` is better treated as an advanced input for known artifact identifiers, not as a documented single-artifact retest entry point.
- **Release**: When a `v*` tag is pushed, `release.yml` promotes only CI artifacts that already passed on the same commit, validates them, compresses them, and creates the GitHub Release.

## License

This project is released under **GPL-3.0**, consistent with the upstream [Landscape Router](https://github.com/ThisSeanZhang/landscape).

If you distribute images built from this project, or modified versions of it, make sure you also comply with the obligations of GPL-3.0.
