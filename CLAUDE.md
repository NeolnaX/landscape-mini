# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

Landscape Mini builds minimal x86 images for Landscape Router.

- Base systems: Debian Trixie / Alpine Linux
- Boot: BIOS + UEFI
- Upstream project: https://github.com/ThisSeanZhang/landscape

## Start here

Choose the path that matches the user’s goal:

1. **Just wants to use the project**
   - Chinese entry: `README.md`
   - English entry: `docs/en/README.md`
   - Custom Build guide: `docs/zh/custom-build.md`, `docs/en/custom-build.md`

2. **Wants to modify the build system or tests**
   - Main files: `build.sh`, `lib/`, `rootfs/`, `tests/`, `.github/workflows/`

3. **Wants release / CI behavior**
   - Read `.github/workflows/ci.yml`
   - Read `.github/workflows/_build-and-validate.yml`
   - Read `.github/workflows/test.yml`
   - Read `.github/workflows/release.yml`

## Common Commands

```bash
make deps           # install local build deps
make deps-test      # install local test deps
make build          # build Debian image
make build-alpine   # build Alpine image
make test           # Debian readiness
make test-dataplane # Debian dataplane
make test-serial    # boot image in QEMU serial mode
make ssh            # SSH into local QEMU on port 2222
```

## Defaults and important inputs

- Default upstream version comes from `build.env` (`LANDSCAPE_VERSION`, currently `v0.18.2`)
- Default Linux login:
  - `root` / `landscape`
  - `ld` / `landscape`
- Default Web UI login:
  - `root` / `root`
- Common build env overrides:
  - `ROOT_PASSWORD`
  - `LANDSCAPE_ADMIN_USER`
  - `LANDSCAPE_ADMIN_PASS`
  - `EFFECTIVE_CONFIG_PATH`
  - `APT_MIRROR`
  - `ALPINE_MIRROR`
  - `OUTPUT_FORMAT`
  - `COMPRESS_OUTPUT`

## Build and test contract

Keep these current behaviors in mind:

- CI and Custom Build both use `.github/workflows/_build-and-validate.yml`
- Each image artifact must include:
  - `.img`
  - `build-metadata.txt`
  - `effective-landscape_init.toml`
- Tests should use the effective topology config, not assume only repo default config
- Tests take credentials from env vars instead of hardcoded values:
  - `SSH_PASSWORD`
  - `API_USERNAME`
  - `API_PASSWORD`

## CI/CD summary

### CI

`ci.yml` builds 4 variants:

- `default`
- `docker`
- `alpine`
- `alpine-docker`

Coverage rule:

- `default` / `alpine`: readiness + dataplane
- `docker` / `alpine-docker`: readiness only, E2E explicitly skipped

### Custom Build

`custom-build.yml` is the fork-friendly manual entry point.

Supports:

- single variant build
- `landscape_version`
- LAN / DHCP inputs
- Linux password
- Web admin username / password

Credential precedence:

- `direct inputs > secrets > defaults`

Secrets names:

- `CUSTOM_ROOT_PASSWORD`
- `CUSTOM_API_USERNAME`
- `CUSTOM_API_PASSWORD`

### Retest

`test.yml` retests existing CI artifacts by `run_id` or artifact suffix and allows credentials to be passed again.

### Release

`release.yml` does **promotion**, not rebuild.

On `v*` tags it:

- finds the successful `ci.yml` run for the same commit on `main`
- downloads validated artifacts
- verifies metadata
- compresses `.img`
- creates the GitHub Release

## Key files

- `build.sh` — main build orchestrator
- `build.env` — default build values
- `lib/common.sh` / `lib/debian.sh` / `lib/alpine.sh` — build implementation
- `configs/landscape_init.toml` — default topology config
- `.github/scripts/render-effective-topology.sh` — renders effective topology config
- `tests/test-readiness.sh` — shared readiness contract
- `tests/test-dataplane.sh` — dataplane test
- `README.md` — Chinese primary entry
- `docs/en/README.md` — English primary entry
- `CONTRIBUTING.md` — branch / PR / release process

## Contribution expectations

- Prefer branch + PR over direct push to `main`
- If the change is user-visible, update `CHANGELOG.md` `Unreleased`
- For CI / workflow / release changes, prefer PR flow
