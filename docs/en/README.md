# Landscape Mini

[![Latest Release](https://img.shields.io/github/v/release/Cloud370/landscape-mini)](https://github.com/Cloud370/landscape-mini/releases/latest)

English | [中文](../../README.md) | [Contributing](../../CONTRIBUTING.md) | [Download Latest Image](https://github.com/Cloud370/landscape-mini/releases/latest)

A minimal x86 image builder for Landscape Router. It supports both **Debian Trixie** and **Alpine Linux** as base systems, produces compact disk images, and supports dual BIOS + UEFI boot.

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
- Build identity is explicit: `base_system + include_docker + output_formats`
- Output formats include `img`, `vmdk`, and `pve-ova`
- Supports both BIOS and UEFI for broad virtualization compatibility
- Fork users can run customized builds directly on GitHub
- GitHub Actions workflows are already set up for automated build, test, and release

## Local Development

If you plan to build locally, debug issues, or validate changes before pushing them, start here.

### Local Build

Local configuration is now layered with this precedence:

`build.env < build.env.<profile> < build.env.local < explicit environment variables`

Recommended usage:

- `build.env`: repository defaults, kept tracked
- `build.env.local`: private machine-specific overrides for passwords, LAN/DHCP, or local test selection
- `build.env.<profile>`: reusable profile-specific overrides such as `lab` or `pve`
- explicit environment variables: one-off overrides such as `LANDSCAPE_ADMIN_USER=bar make build`

```bash
# Install build dependencies (first time only)
make deps

# Default combination: debian + no-docker + img
make build

# Use a profile: build.env.lab
BUILD_ENV_PROFILE=lab make build

# Local private overrides: build.env.local
make build

# Explicit overrides still win over env files
LANDSCAPE_ADMIN_USER=admin RUN_TEST=readiness make build

# Alpine raw image
make build BASE_SYSTEM=alpine

# Debian + Docker + img,pve-ova
make build INCLUDE_DOCKER=true OUTPUT_FORMATS=img,pve-ova
```

Common local customization inputs now include:

- `LANDSCAPE_ADMIN_USER` / `LANDSCAPE_ADMIN_PASS`
- `LANDSCAPE_LAN_SERVER_IP` / `LANDSCAPE_LAN_RANGE_START` / `LANDSCAPE_LAN_RANGE_END` / `LANDSCAPE_LAN_NETMASK`
- `RUN_TEST`

### Local Test

```bash
# Automated readiness checks (non-interactive)
make deps-test
make test

# Dataplane tests only apply to include_docker=false raw images
make test-dataplane

# Or run validation automatically after a build
RUN_TEST=readiness make build
RUN_TEST=readiness,dataplane make build

# When INCLUDE_DOCKER=true, requested dataplane is skipped explicitly
INCLUDE_DOCKER=true RUN_TEST=readiness,dataplane make build

# Or point tests at any raw image directly
./tests/test-readiness.sh output/landscape-mini-x86-alpine.img
./tests/test-dataplane.sh output/landscape-mini-x86-debian.img

# Interactive boot (serial console)
make test-serial
```

## Deployment

### Physical Machine / USB Drive

```bash
dd if=output/landscape-mini-x86-debian.img of=/dev/sdX bs=4M status=progress
```

### Proxmox VE (PVE)

Two recommended paths:

#### Option 1: Use `pve-ova`

- Include `pve-ova` in `OUTPUT_FORMATS`
- Upload the generated `.ova`
- Import it in PVE, then verify boot mode, disk controller, and bridge assignment

#### Option 2: Use the raw `.img`

1. Upload the image to the PVE host.
2. Create a VM without attaching a disk.
3. Import the disk: `qm importdisk <vmid> landscape-mini-x86-debian.img local-lvm`
4. Attach the imported disk in the VM hardware settings.
5. Set the boot order and start the VM.

### Cloud Server (dd Script)

Use the [reinstall](https://github.com/bin456789/reinstall) script to write the custom image onto a cloud server:

```bash
bash <(curl -sL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh) \
    dd --img='https://github.com/Cloud370/landscape-mini/releases/latest/download/landscape-mini-x86-debian.img.gz'
```

> The root partition automatically expands on first boot to fill the entire disk. No manual intervention is required.

## Default Credentials

| Scenario | Username | Password |
|------|------|------|
| SSH / system login | `root` | `landscape` |
| SSH / system login | `ld` | `landscape` |
| Web UI | `root` | `root` |

> `custom-build.yml` can override Linux and Web UI credentials through workflow inputs or GitHub Secrets. Plaintext inputs are fine for temporary personal use; if security matters, prefer `CUSTOM_ROOT_PASSWORD`, `CUSTOM_API_USERNAME`, and `CUSTOM_API_PASSWORD`.

## Build Configuration

Avoid treating tracked `build.env` as the primary place for day-to-day customization. Prefer:

- `build.env.local`
- `build.env.<profile>`
- explicit environment variables
- GitHub Actions `Custom Build`

| Variable | Default | Description |
|------|--------|------|
| `BASE_SYSTEM` | `debian` | Base system: `debian` / `alpine` |
| `INCLUDE_DOCKER` | `false` | Include Docker: `true` / `false` |
| `OUTPUT_FORMATS` | `img` | Ordered output formats: `img`, `vmdk`, `pve-ova` (comma-separated) |
| `RUN_TEST` | _(empty)_ | Local test selection: empty / `none`, `readiness`, `readiness,dataplane` |
| `LANDSCAPE_ADMIN_USER` | `root` | Web admin username |
| `LANDSCAPE_ADMIN_PASS` | `root` | Web admin password |
| `LANDSCAPE_LAN_SERVER_IP` | _(empty)_ | LAN gateway / DHCP service IP |
| `LANDSCAPE_LAN_RANGE_START` | _(empty)_ | LAN DHCP range start |
| `LANDSCAPE_LAN_RANGE_END` | _(empty)_ | LAN DHCP range end |
| `LANDSCAPE_LAN_NETMASK` | _(empty)_ | LAN subnet prefix length, for example `24` |
| `APT_MIRROR` | _(auto probe)_ | Explicit Debian package mirror override; if empty, probe candidates |
| `ALPINE_MIRROR` | _(auto probe)_ | Explicit Alpine package mirror override; if empty, probe candidates |
| `DOCKER_APT_MIRROR` | _(auto probe)_ | Explicit Debian Docker APT repository override |
| `DOCKER_APT_GPG_URL` | _(auto probe)_ | Explicit Debian Docker APT GPG URL override |
| `LANDSCAPE_VERSION` | `v0.18.2` | Upstream Landscape version |
| `LANDSCAPE_REPO` | `https://github.com/ThisSeanZhang/landscape` | Upstream Landscape release repository |
| `IMAGE_SIZE_MB` | `2048` | Initial image size (automatically shrunk later) |
| `ROOT_PASSWORD` | `landscape` | Login password for `root` / `ld` |
| `TIMEZONE` | `Asia/Shanghai` | Time zone |
| `LOCALE` | `C.UTF-8` | System locale |

### Custom Builds (GitHub Actions)

The repository provides `custom-build.yml` as a tuple-based build entry point for fork users. It supports:

- `base_system`: `debian` / `alpine`
- `include_docker`: `true` / `false`
- `output_formats`
- `landscape_version`
- `lan_server_ip` / `lan_range_start` / `lan_range_end` / `lan_netmask`
- `root_password`
- `api_username` / `api_password`
- `run_test`

Current precedence: **direct inputs > secrets > defaults**.

The shared test contract is now:

- empty / `none`: build only
- `readiness`
- `readiness,dataplane`

When `include_docker=true`, requested dataplane is skipped explicitly with a reason in the logs.

The workflow writes the following build identity fields into `build-metadata.txt`:

- `base_system`
- `include_docker`
- `output_formats`
- `run_test`
- `produced_files`
- `artifact_id`
- `release_channel`

The effective network topology is bundled as `effective-landscape_init.toml` so `test.yml`, fixed-release publishing, and tag release rebuild validation can use it.

Successful Custom Build runs also publish to a fixed tag in the fork: `custom-build-latest`.
It is a fixed entry point for the latest successful Custom Build, not a tuple-specific permanent download slot; any later successful Custom Build (for example Debian / Alpine, Docker / non-Docker) replaces its contents.

- Release page: `https://github.com/<owner>/landscape-mini/releases/tag/custom-build-latest`
- Direct download base: `https://github.com/<owner>/landscape-mini/releases/download/custom-build-latest/<asset>`

If you need immutable build outputs, use the Artifacts from the corresponding workflow run or record the `run_id` / `artifact_id`.

## Automated Testing

### Readiness Checks

`make test` or `./tests/test-readiness.sh <image.img>` run the shared router readiness contract:

1. Copy the image to a temporary file to protect build artifacts.
2. Start QEMU in the background with automatic KVM detection.
3. Wait for SSH, API listener, API login, and layout detection.
4. Verify `eth0` / `eth1` and ensure core services reach the running state.
5. When `include_docker=true`, additionally verify Docker is functional.
6. Output readiness, service, and diagnostics snapshots, then clean up QEMU.

### Dataplane Tests

`make test-dataplane` or `./tests/test-dataplane.sh <image.img>` validate real client-visible dataplane behavior with a two-VM topology:

```text
Router VM (eth0=WAN/SLIRP, eth1=LAN/mcast) ←→ Client VM (CirrOS, eth0=mcast)
```

Coverage includes DHCP lease assignment, lease visibility in the Router API, and LAN connectivity between the router and client.

> Dataplane scheduling is based on `include_docker=false`, not on legacy variant names.

## CI/CD

- **CI**: Manual runs are always available. On pushes to `main` and pull requests, workflows run automatically only when build-related files, relevant files under `.github/`, or `CHANGELOG.md` change.
- **Automatic CI validation surface**: only `debian + include_docker=false`, requesting raw `img` only.
- **Readiness / dataplane coverage**: automatic CI runs `readiness,dataplane` for `include_docker=false`.
- **Artifact contract**: every image artifact includes raw `.img`, `build-metadata.txt`, and `effective-landscape_init.toml`; automatic CI no longer exports `.vmdk` / `.ova`.
- **Custom Build**: `custom-build.yml` lets fork users build explicit tuples with custom LAN/DHCP settings, Linux password, Web UI credentials, and `run_test` selection.
- **Manual Retest**: `test.yml` retests the Debian default public tuples by `run_id` or `artifact_id`, with SSH / API credentials passed in again.
- **Release**: when a `v*` tag is pushed, `release.yml` rebuilds Debian Docker / non-Docker artifacts from that tagged commit instead of promoting CI artifacts, and publishes the default public surface: `.img.gz` + `.ova`.
- **Alpine**: Alpine is no longer part of the default public release surface; use `Custom Build` when you need it.

## License

This project is released under **GPL-3.0**, consistent with the upstream [Landscape Router](https://github.com/ThisSeanZhang/landscape).
