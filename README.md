# Custom ISO Builder

**Version:** 0.3.4

Automated Debian and Ubuntu custom ISO creation with preseed/autoinstall for unattended installations.
Designed for VMware ESXi but compatible with any hypervisor or USB boot.

# Features

- ✅ **Automated dependency installation** (xorriso, isolinux, preseed-creator)
- ✅ **Smart logging** with verbose mode
- ✅ **SSH connectivity validation** before upload
- ✅ **Configurable upload toggle** (local-only or remote)
- ✅ **ISO source caching** and override options
- ✅ **SHA256 checksum generation**
- ✅ **Clean working directory management**
- ✅ **Debian preseed files** support
- ✅ **Ubuntu autoinstall files** support
- ✅ **VMware ESXi integration** with SSH upload
- ✅ **Docker support** for isolated builds
- ✅ **Cloud-init compatibility** for post-installation configuration

### Generate User Passwords

```bash
openssl passwd -6 -salt "$(openssl rand -hex 8)" secret
```

# Quick Start

## 1. Configure Environment

Copy and edit the environment template:

```bash
cp .env.example .env
```

Edit `.env` with your ESXi host and SSH credentials.

### `.env` Configuration Variables

ISO Uploads target vCenter hypervisor, so the .env reflects that.
If you do not use vCenter, just set the c`onfigs/custom-iso-builder.cfg` parameter to `UPLOAD_CUSTOM_ISO=false`
and find your way to upload your .iso image. 
I may try to provide a more agnostic way to upload .iso on other targets, next in line would be Proxmox.


| Variable | Description | Example |
|----------|-------------|---------|
| `VMWARE_SSH_HOST_CONFIG` | SSH host from `~/.ssh/config` | `my_esxi_host.mydomain.tld` |
| `VMWARE_DATASTORE` | ESXi datastore name | `datastore1` |
| `VMWARE_ISO_DIRPATH` (*) | Directory path in datastore to store your ISOs | `ISO/LINUX` |
| `VMWARE_VOLUMES_PATH` (*) | Auto-constructed volumes path | `/vmfs/volumes` |
| `VMWARE_DATASTORE_PATH` (*) | Auto-constructed datastore path | `${VMWARE_VOLUMES_PATH}/${VMWARE_DATASTORE}` - `/vmfs/volumes/datastore1` |
| `VMWARE_ISO_UPLOAD_PATH` (*) | Auto-constructed upload path | `${VMWARE_DATASTORE_PATH}/${VMWARE_ISO_DIRPATH}` - `/vmfs/volumes/datastore1/ISO/LINUX` |

(*): # Your custom .iso  will be uploaded to: /vmfs/volumes/<VMWARE_DATASTORE>/<VMWARE_ISO_DIRPATH>/

## 2. Configure ISO Builder

Edit `configs/custom-iso-builder.cfg`:

### `custom-iso-builder.cfg` Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AUTO_INSTALL_DEPS` | Auto-install missing dependencies | `true` |
| `OVERRIDE_EXISTING_SOURCE_ISO` | Re-download source ISO if exists | `false` |
| `OVERRIDE_EXISTING_CUSTOM_ISO` | Overwrite existing custom ISO | `true` |
| `UPLOAD_CUSTOM_ISO` | Upload to remote host | `true` |
| `VALIDATE_SSH_TARGET` | Validate SSH before upload | `true` |
| `KEEP_WORKING_DIRECTORY` | Keep working directory for debugging | `false` |
| `VERBOSE_MODE` | Enable debug logging | `true` |

## 3. Create OS Configuration

The custom-iso script will look into `configs/build/` and throw an error if more than one file is present.
This is by design as I want to use git commits to trigger the builds.

- I may eventually add batch creation of multiple .iso if it proves usefull.

  It is not really planned as it adds loops etc and would be more painfull to debug if one of the images where to be failing.
  For now, I prefer a commit per new .iso I want to create.


Create your Debian or Ubuntu config file in `configs/available/` following the templates:

- `configs/templates/debian-13.1.0-example.cfg`
- `configs/templates/ubuntu-25.10-example.cfg`

Place **one** config file in `configs/build/` to trigger the build.

### Debian Configuration Example (`debian-13.1.0.cfg`)

```bash
# Linux OS Type Family (use lowercase names like 'debian' or 'ubuntu')
linux_os_type="debian"

# Debian version and ISO variables
debian_version="13.1.0"
debian_codename="trixie"
debian_arch="amd64"
debian_iso_name="debian-${debian_version}-${debian_arch}-DVD-1.iso"
iso_url="https://cdimage.debian.org/cdimage/archive/${debian_version}/${debian_arch}/iso-dvd/debian-${debian_version}-${debian_arch}-DVD-1.iso"
iso_checksum="https://cdimage.debian.org/cdimage/archive/${debian_version}/${debian_arch}/iso-dvd/SHA512SUMS"
iso_volume_name="debian-${debian_version}-${debian_arch}-netinst.iso"

# File names (directories are hardcoded for Docker compatibility)
config_file="debian-${debian_version}.cfg"
preseed_template="preseed_debian-${debian_version}-template.cfg"
preseed_file="preseed_debian-${debian_version}.cfg"

# Custom ISO output name
custom_iso_version="1.0.1"
custom_iso_comment="custom"
custom_iso_name="debian-${debian_version}-${debian_arch}-${custom_iso_comment}-${custom_iso_version}.iso"
```

### Ubuntu Configuration Example (`ubuntu-25.10.cfg`)

```bash
# Linux OS Type Family (use lowercase names like 'debian' or 'ubuntu')
linux_os_type="ubuntu"

# Ubuntu version and ISO variables
debian_version="25.10"
debian_codename="noble"
debian_arch="amd64"
debian_iso_name="ubuntu-${debian_version}-live-server-${debian_arch}.iso"
iso_url="https://releases.ubuntu.com/${debian_version}/${debian_iso_name}"
iso_volume_name="ubuntu-${debian_version}-${debian_arch}-netinst.iso"

# File names (directories are hardcoded for Docker compatibility)
config_file="ubuntu-${debian_version}.cfg"
preseed_template="autoinstall_ubuntu-${debian_version}-template.yml"
preseed_file="autoinstall_ubuntu-${debian_version}.yml"
user_data_template="autoinstall_ubuntu-${debian_version}-template.yml"
user_data_file="autoinstall_ubuntu-${debian_version}.yml"
meta_data_file="meta-data"

# Custom ISO output name
custom_iso_version="1.0.1"
custom_iso_comment="custom"
custom_iso_name="ubuntu-${debian_version}-${debian_arch}-${custom_iso_comment}-${custom_iso_version}.iso"
```

# 4. Preseed / Autoinstall Files

Here It is mostly on you, but the templates may help you if you start from zero. 
Many things are missing and for Example I do not deal (yet ) with LUKS or custom disc formating etc... for now it is basic standard disk formating.
Basically any preseed or autoinstal file that worked for you should work with the script.


Preseed files (Debian) and autoinstall files (Ubuntu) are stored in `preseeds/`.

- **Debian**: Use `preseed_debian-<version>.cfg`
- **Ubuntu**: Use `autoinstall_ubuntu-<version>.yml`

Examples are provided in the `preseeds/` directory.

### Relations between Debian/Ubuntu Config files and Debien Preseed / Ubuntu autoinstall files

You have to point your preseed / autoinstall files inside the config files.

- Preseed / autoinstall only concern what you build inside the .iso
- config files are more a way declarative to name your custom iso, provide debian/ ubuntu .iso URLs, etc...

Naming is based on Debian and ubuntu ISO names or URLs. You can find example in templates.
Nothing blocks you to completely change the way I labeled custom .iso, or how I set the download URLS.
I just find it simpler to:
- just give the actual Debain or Ubuntu versions eg: 12.9.0, 13.1.0, 25.10
- set a Version Number for my  custom iso
- set a "comment" eg: CloudinitTest, CLoudInitReady, Dev

For ex: 

- `debian-13.1.0-amd64-CloudInitTest-1.1.1-a.iso`
- `ubuntu-25.10-live-server-amd64-vmware_tests-0.1.1.iso`

# 5. Usage

## Run the Script locally

The script can be runned locally but the main goal is to use docker container. It aloows me to create all my Debian / Ubuntu custom .ISO right on my MacbookPro.

You'll need sudo to run the script.

```bash
sudo ./create-iso.sh
```

The custom ISO will be created in the `ISOs/` directory and automatically uploaded to ESXi if you set `UPLOAD_CUSTOM_ISO=true`.

## Use Docker

The default behavior is to terminate the container after build ( either success or failure).
If you encounters issues, you may want to check things in the container. 



### Build the Docker Image

```bash
docker-compose build --no-cache
```

When testing you can add `--no-cache` to `docker-compose build`

### Run the Container

```bash
docker-compose up
```

Or in detached mode:

```bash
docker-compose up -d
```

### Debugging
If you want to perform tests (eg: check ssh config or run the script manually inside the container).
There is an option to keep the container running after the build and do some debug if needed.
Edit `.env` and set `ISO_BUILDER_KEEP_ALIVE=true` to keep the ISO builder container alive after the iso build,
otherwise set it to `false`

1. Edit `.env` and set:
 
   ```bash
   ISO_BUILDER_KEEP_ALIVE=true
   ```

2. Run the container:
 
   ```bash
   docker-compose up
   ```

3. Access the container:

   ```bash
   docker exec -it iso-builder /bin/bash
   ```

### View Logs

```bash
docker logs -f iso-builder
```

## Configuration Details

### Directory Structure

```
configs/        # Debian/Ubuntu version configs
├── available/  # Available configurations
├── build/      # Active configuration (one file only)
└── templates/  # Configuration templates

preseeds/       # Preseed/autoinstall files
ISOs/           # Source and custom ISOs
```

### SSH Configuration

The script relies on `~/.ssh/config` for SSH authentication. Ensure your SSH key is properly configured.
I found it easier to manage credential etc.. when I use it locally.
I plan to work again on other ways, mainly to use this repo in my Gitlab. And tirgger it when I commit a New Debian Config / preseed or ubuntu config / autoinstall.

### Network Requirements

- **Local use**: Cloudflare WARP or Tailscale recommended
- **SSH target**: Must be reachable when `UPLOAD_CUSTOM_ISO=true`

## Requirements

- Debian/Ubuntu Linux
- sudo access
- SSH key authentication for ESXi upload

## TODOs

- [ ] ISOs Subfolders {Source,Custom}
- [ ] Verify remote checksum after upload
- [ ] Variable substitution in preseed files
- [ ] Multi-target support (Proxmox, AWS, etc.)
- [ ] variable substitutions in preseed file (LATER USE)
- [ ] envsubst < ${install_config_template_path} > ${install_config_file_path}
- [ ] wget ${iso_checksum} -O SHA256SUMS
- [ ] grep "${debian_iso_name}" SHA256SUMS | sha256sum -c -
- [ ] todo: detect if isolinux exists for older versions (LATER USE)
- [ ] Create remote directory on ssh host if it doesn't exist (LATER USE)
- [ ] Loading bar for ssh upload (LATER USE)
- [ ] Parallel ssh upload (LATER USE)
- [ ] Check if remote ISO file exists on ssh host
- [ ] Upload to temp directory on ssh host first



## Cloudflare Note

To download `preseed-creator` with `wget` or `curl`, add **framagit.org** to a **"Do Not Inspect"** Cloudflare Gateway HTTP policy.

## Main Contributor

oem <oem@mobiloem>
