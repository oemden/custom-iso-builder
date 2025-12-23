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

## Configuration

Edit `.env` to customize behavior:
- `AUTO_INSTALL_DEPS` - Auto-install missing tools
- `UPLOAD_CUSTOM_ISO` - Enable/disable remote upload
- `VALIDATE_SSH_TARGET` - Check SSH before upload
- `OVERRIDE_EXISTING_CUSTOM_ISO` - Overwrite existing ISOs
- `VERBOSE_MODE` - Enable debug logging

See `.env.example` for full documentation.

## Directory Structure

```
config/     - Debian version configs
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
- [ ] Docker/docker-compose support
- [ ] Multi-target support (Proxmox, AWS, etc.)

## Main Contributor

oem <oem@mobiloem>
