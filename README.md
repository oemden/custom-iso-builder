# Custom ISO Builder

**Version:** 0.2.0

Automated Debian custom ISO creation with preseed for unattended installations.
Designed for VMware ESXi but works with any hypervisor or USB boot.

## Features

- ✅ Automated dependency installation (xorriso, isolinux, preseed-creator)
- ✅ Smart logging with verbose mode
- ✅ SSH connectivity validation before upload
- ✅ Configurable upload toggle (local-only or remote)
- ✅ ISO source caching and override options
- ✅ SHA256 checksum generation
- ✅ Clean working directory management

### generqte user passwords:

```
$ openssl passwd -6 -salt "$(openssl rand -hex 8)" secret
```

TODOs: var substitution for preseed and autoinstall files.

## Quick Start

```bash
# 1. Copy and configure environment
cp .env.example .env
# Edit .env with your ESXi host and credentials

# 2. Run the script
./create-iso.sh

# Custom ISO will be created in ISOs/ directory
# Automatically uploaded to ESXi if UPLOAD_CUSTOM_ISO=true
```

### Local Docker tests

edit docker-compose.yml

```bash
dockerfile: Dockerfile-root
```

build the image with no cache

```bash
docker-compose build --no-cache
```

If you want to perform tests (eg: check ssh config or run the script manually )
Edit `.env` and set `ISO_BUILDER_KEEP_ALIVE=true` to keep the ISO builder container alive after the iso build`

run the container 

```bash
docker-compose up
```
or

```bash
docker-compose up -d
docker logs -f iso-builder
```

then 

```bash
docker exec  -it iso-builder /bin/bash 
```

## Configuration

Edit `configs/custom-iso-builder.cfg` to customize scripts behavior:
- `AUTO_INSTALL_DEPS` - Auto-install missing tools
- `UPLOAD_CUSTOM_ISO` - Enable/disable remote upload
- `VALIDATE_SSH_TARGET` - Check SSH before upload
- `OVERRIDE_EXISTING_CUSTOM_ISO` - Overwrite existing ISOs
- `VERBOSE_MODE` - Enable debug logging

See `configs/custom-iso-builder-example.cfg` for full documentation.

## Directory Structure

```
configs/    - Debian version configs
preseeds/   - Preseed templates
ISOs/       - Source and custom ISOs
```

## Requirements

- Debian/Ubuntu Linux
- sudo access
- SSH key authentication for ESXi upload

## TODOs

- [ ] Verify remote checksum after upload
- [ ] Variable substitution in preseed files
- [x] Docker/docker-compose support
- [ ] Multi-target support (Proxmox, AWS, etc.)

## Cloudflare

To get docker build download `preseed-creator` ( with `wget` or `curl` ) I had to add **framagit.org** to a **"Do Not Inspect"** Gateway HTTP policy.

## Main Contributor

oem <oem@mobiloem>
