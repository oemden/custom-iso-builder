#!/bin/bash
#================================
# Custom ISO Builder
#================================
# This script creates a customized Debian ISO with a preseed file for automated installation.
# iso creation based on preseed-creator tool: https://framagit.org/fiat-tux/hat-softwares/preseed-creator/

SCRIPT_VERSION="0.2.2"

#--- Logging functions ---
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$level] $timestamp - $*"
}

log_verbose() {
    if [ "$VERBOSE_MODE" = "true" ]; then
        log "DEBUG" "$@"
    fi
}

log_error() {
    log "ERROR" "$@" >&2
}

log_success() {
    log "SUCCESS" "$@"
}

#--- must run sudo
if [ `id -u` -ne 0 ] ; then
	printf " == Must be run as sudo, exiting == "
    log_error "This script requires root privileges. Please run as root or use sudo."
	echo 
	exit 1
fi

#--- Docker Detection ---
# Detect if running inside Docker container
if [ -f /.dockerenv ] || [ "$DOCKER_CONTAINER" = "true" ]; then
    RUNNING_IN_DOCKER=true
    dirpath="/app"
else
    RUNNING_IN_DOCKER=false
    dirpath=$(pwd)
fi

# Hardcoded paths (for Docker compatibility)
CONFIG_DIR="configs"
BUILD_DIR="${CONFIG_DIR}/build"
SCRIPT_OPTIONS="${CONFIG_DIR}/custom-iso-builder.cfg"
PRESEED_DIR="preseeds"
ISO_DIR="ISOs"
WORKING_DIR="custom-iso-workdir"

log "echo variables"
extra_output

log "INFO" "Loading Script options"

#--- Load Configuration ---
if [ ! -f "${dirpath}/${SCRIPT_OPTIONS}" ]; then
    log "INFO" "script options file not found: ${SCRIPT_OPTIONS}"
    log "INFO" "Please create custom-iso-builder.cfg from custom-iso-builder-example.cfg in ${CONFIG_DIR}/"
    log "INFO" "loading defaults options"
elif [ -f "${dirpath}/${SCRIPT_OPTIONS}" ]; then
    log "INFO" "Sourcing script options from ${SCRIPT_OPTIONS}..."
    source "${dirpath}/${SCRIPT_OPTIONS}"
    if [ $? -ne 0 ]; then
        log_error "Failed to source script options file: ${SCRIPT_OPTIONS}"
        exit 1
    fi
fi

#--- Load Build Config ---
log "INFO" "Loading Debian version configuration..."

# Look for config file in configs/build/ directory
build_dir="${dirpath}/${BUILD_DIR}"
config_files=("${build_dir}"/*.cfg)

if [ ${#config_files[@]} -eq 0 ] || [ ! -f "${config_files[0]}" ]; then
    log_error "No config file found in ${build_dir}/"
    log_error "Copy a config file to configs/build/ to proceed"
    exit 1
elif [ ${#config_files[@]} -eq 1 ]; then
    config_file=$(basename "${config_files[0]}")
    log "INFO" "Found config in build/: ${config_file}"
    source "${build_dir}/${config_file}"
    if [ $? -ne 0 ]; then
        log_error "Failed to source config file: ${config_file}"
        exit 1
    fi
else
    log_error "Multiple config files found in ${build_dir}/"
    log_error "Only one config allowed in build/ directory"
    for cfg in "${config_files[@]}"; do
        log_error "  - $(basename "$cfg")"
    done
    exit 1
fi

log_verbose "Configuration loaded successfully"
log_verbose "Debian version: ${debian_version}"
log_verbose "Working directory: ${dirpath}"

#--- Preseed file preparation ---
log "INFO" "Checking preseed file..."
preseed_template_path="${dirpath}/${PRESEED_DIR}/${preseed_template}"
preseed_file_path="${dirpath}/${PRESEED_DIR}/${preseed_file}"

if [[ ! -f "${preseed_template_path}" ]] && [[ ! -f "${preseed_file_path}" ]]; then
  log_error "Preseed file ${preseed_file_path} or template ${preseed_template_path} not found!"
  exit 1
elif [[ -f "${preseed_template_path}" ]] && [[ ! -f "${preseed_file_path}" ]]; then
  log "INFO" "No preseed file found, copying template to ${preseed_file}"
  cp "${preseed_template_path}" "${preseed_file_path}"
  log_verbose "Preseed file created from template"
else
  log_verbose "Preseed file exists: ${preseed_file}"
fi

# TODO: variable substitutions in preseed file (LATER USE)
# export PRESEED_NETCFG_HOSTNAME PRESEED_NETCFG_DOMAIN
# envsubst < ${preseed_template_path} > ${preseed_file_path}

#--- Dependency checking and installation ---
check_and_install_dependencies() {
    local deps_missing=false

    log "INFO" "Checking dependencies..."

    # Check xorriso
    if ! command -v xorriso &> /dev/null; then
        log "WARN" "xorriso not found"
        deps_missing=true
    else
        log_verbose "✓ xorriso installed"
    fi

    # Check isolinux
    if ! dpkg -l 2>/dev/null | grep -q "^ii  isolinux"; then
        log "WARN" "isolinux not found"
        deps_missing=true
    else
        log_verbose "✓ isolinux installed"
    fi

    # Check preseed-creator
    if ! command -v preseed-creator &> /dev/null; then
        log "WARN" "preseed-creator not found"
        deps_missing=true
    else
        log_verbose "✓ preseed-creator installed"
    fi

    # Install if missing and AUTO_INSTALL_DEPS=true
    if [ "$deps_missing" = "true" ]; then
        if [ "$AUTO_INSTALL_DEPS" = "true" ]; then
            log "INFO" "Installing missing dependencies..."
            install_dependencies
        else
            log_error "Missing dependencies. Set AUTO_INSTALL_DEPS=true in .env to auto-install"
            exit 1
        fi
    else
        log "INFO" "✓ All dependencies satisfied"
    fi
}

install_dependencies() {
    # xorriso and isolinux
    if ! command -v xorriso &> /dev/null || ! dpkg -l 2>/dev/null | grep -q "^ii  isolinux"; then
        log "INFO" "Installing xorriso and isolinux..."
        apt-get update -qq
        apt-get install -y xorriso isolinux || {
            log_error "Failed to install xorriso/isolinux"
            exit 1
        }
        log_verbose "✓ xorriso and isolinux installed"
    fi

    # preseed-creator
    if ! command -v preseed-creator &> /dev/null; then
        log "INFO" "Installing preseed-creator..."
        wget -q https://framagit.org/fiat-tux/hat-softwares/preseed-creator/-/raw/main/preseed-creator || {
            log_error "Failed to download preseed-creator"
            exit 1
        }
        chmod +x preseed-creator
        mv preseed-creator /usr/local/bin/ || {
            log_error "Failed to install preseed-creator"
            exit 1
        }
        log_verbose "✓ preseed-creator installed"
    fi

    log "INFO" "✓ Dependencies installed successfully"
}

# Run dependency check
check_and_install_dependencies

#--- Download Debian source ISO ---
log "INFO" "Checking Debian source ISO..."
mkdir -p "${dirpath}/${ISO_DIR}"
iso_path="${dirpath}/${ISO_DIR}/${debian_iso_name}"

if [ -f "${iso_path}" ]; then
    if [[ "${OVERRIDE_EXISTING_SOURCE_ISO}" = "true" ]]; then
        log "INFO" "Source ISO exists but OVERRIDE_EXISTING_SOURCE_ISO=true, re-downloading..."
        rm -f "${iso_path}"
        log "INFO" "Downloading Debian ${debian_version} ISO from ${iso_url}..."
        wget "${iso_url}" -O "${iso_path}" || {
            log_error "Failed to download Debian ISO!"
            exit 1
        }
        log_success "Downloaded ${debian_iso_name}"
    else
        log "INFO" "Source ISO already exists, skipping download"
        log_verbose "ISO path: ${iso_path}"
    fi
else
    log "INFO" "Source ISO not found, downloading..."
    log "INFO" "Downloading Debian ${debian_version} from ${iso_url}..."
    wget "${iso_url}" -O "${iso_path}" || {
        log_error "Failed to download Debian ISO!"
        exit 1
    }
    log_success "Downloaded ${debian_iso_name}"
fi

# TODO: Verify ISO checksum (LATER USE)
# wget ${iso_checksum} -O SHA256SUMS
# grep "${debian_iso_name}" SHA256SUMS | sha256sum -c -

#--- Create customized ISO ---
log "INFO" "Creating customized ISO with preseed..."
working_dir_path="${dirpath}/${WORKING_DIR}"
mkdir -p "${working_dir_path}"

# Check if destination ISO exists
custom_iso_path="${dirpath}/${ISO_DIR}/${custom_iso_name}"
if [[ -f "${custom_iso_path}" ]]; then
  if [[ "${OVERRIDE_EXISTING_CUSTOM_ISO}" = "true" ]]; then
    log "INFO" "Custom ISO exists, backing up as ${custom_iso_name}.old"
    mv "${custom_iso_path}" "${custom_iso_path}.old"
  else
    log_error "Custom ISO ${custom_iso_name} already exists. Set OVERRIDE_EXISTING_CUSTOM_ISO=true to overwrite."
    exit 1
  fi
fi

log "INFO" "Running preseed-creator..."
log_verbose "Source: ${iso_path}"
log_verbose "Output: ${custom_iso_path}"
log_verbose "Preseed: ${preseed_file_path}"


/usr/local/bin/preseed-creator \
  -i "${iso_path}" \
  -o "${custom_iso_path}" \
  -p "${preseed_file_path}" \
  -x -t 3 \
  -v || {
    log_error "Failed to create customized ISO!"
    exit 1
  }
#   -w "${working_dir_path}" \

log_success "Custom ISO created: ${custom_iso_name}"

#--- Generate checksum ---
log "INFO" "Generating SHA256 checksum..."
custom_iso_checksum=$(sha256sum "${custom_iso_path}" | awk '{print $1}')
custom_iso_checksum_file="${custom_iso_path}.md5"
echo "${custom_iso_checksum}" > "${custom_iso_checksum_file}"
log_verbose "Checksum: ${custom_iso_checksum}"
log_success "Checksum saved to ${custom_iso_name}.md5"

#--- Echo variables ---
function extra_output() {
echo "-------"
echo "Source: ${iso_path}" ; ls -l "${iso_path}"
echo "Output: ${custom_iso_path}" 
echo "Preseed: ${preseed_file_path}" ; ls -l "${preseed_file_path}"
echo "working_dir_path: ${working_dir_path}" ; ls -l "${working_dir_path}"
echo "AUTO_INSTALL_DEPS: ${AUTO_INSTALL_DEPS}" 
echo "OVERRIDE_EXISTING_SOURCE_ISO: ${OVERRIDE_EXISTING_SOURCE_ISO}" 
echo "OVERRIDE_EXISTING_CUSTOM_ISO: ${OVERRIDE_EXISTING_CUSTOM_ISO}" 
echo "UPLOAD_CUSTOM_ISO: ${UPLOAD_CUSTOM_ISO}" 
echo "VALIDATE_SSH_TARGET: ${VALIDATE_SSH_TARGET}" 
echo "KEEP_WORKING_DIRECTORY: ${KEEP_WORKING_DIRECTORY}" 
echo "VERBOSE_MODE: ${VERBOSE_MODE}" 
echo "VMWARE_SSH_HOST_CONFIG: ${VMWARE_SSH_HOST_CONFIG}"
echo "VMWARE_SSH_HOST_CONFIG: $VMWARE_SSH_HOST_CONFIG"
echo "VMWARE_DATASTORE: $VMWARE_DATASTORE"
echo "VMWARE_ISO_DIRPATH: $VMWARE_ISO_DIRPATH"
echo "VMWARE_VOLUMES_PATH: $VMWARE_VOLUMES_PATH"
echo "VMWARE_DATASTORE_PATH: $VMWARE_DATASTORE_PATH"
echo "VMWARE_ISO_UPLOAD_PATH: $VMWARE_ISO_UPLOAD_PATH"
echo "-------"
}

extra_output

#--- SSH Target Validation ---
validate_ssh_target() {
    # Check if SSH target is configured
    if [ -z "$VMWARE_SSH_HOST_CONFIG" ]; then
        log_error "VMWARE_SSH_HOST_CONFIG not set in .env"
        return 1
    fi

    # Skip validation if explicitly disabled
    if [ "$VALIDATE_SSH_TARGET" != "true" ]; then
        log "WARN" "SSH target validation disabled (VALIDATE_SSH_TARGET=false)"
        return 0
    fi

    # Check if target is reachable
    log "INFO" "Validating SSH connectivity to ${VMWARE_SSH_HOST_CONFIG}..."

    #####################
    log_verbose "DEBUG: HOME=$HOME"
    log_verbose "DEBUG: USER=$USER"
    log_verbose "DEBUG: whoami=$(whoami)"
    log_verbose "DEBUG: SSH config check:"
    ls -la ~/.ssh/ || echo "~/.ssh not found"
    ls -la $HOME/.ssh/ || echo "\$HOME/.ssh not found"
    #####################

    # if ssh -o ConnectTimeout=5 -o BatchMode=yes "$VMWARE_SSH_HOST_CONFIG" "echo 'SSH OK'" &>/dev/null; then
    #     log_success "✓ SSH target ${VMWARE_SSH_HOST_CONFIG} is reachable"
    #     return 0
    # else
    #     log_error "✗ Cannot reach SSH target ${VMWARE_SSH_HOST_CONFIG}"
    #     log_error "  Check: 1) SSH config, 2) Network (Cloudflare WARP/Tailscale), 3) Target host"
    #     return 1
    # fi
    log "INFO" "Validating SSH connectivity to ${VMWARE_SSH_HOST_CONFIG}..."

    # Debug output
    log_verbose "Running: ssh -v -o ConnectTimeout=5 -o BatchMode=yes \"$VMWARE_SSH_HOST_CONFIG\" \"echo 'SSH OK'\""

    # Run with verbose to capture errors
    ssh_output=$(ssh -vv -o ConnectTimeout=5 -o BatchMode=yes "$VMWARE_SSH_HOST_CONFIG" "echo 'SSH OK'" 2>&1)
    ssh_exit_code=$?

    if [ $ssh_exit_code -eq 0 ]; then
        log_success "✓ SSH target ${VMWARE_SSH_HOST_CONFIG} is reachable"
        return 0
    else
        log_error "✗ Cannot reach SSH target ${VMWARE_SSH_HOST_CONFIG}"
        log_error "SSH exit code: $ssh_exit_code"
        log_error "SSH output:"
        echo "$ssh_output" | while IFS= read -r line; do
            log_error "  $line"
        done
        log_error "  Check: 1) SSH config, 2) Network (Cloudflare WARP/Tailscale), 3) Target host"
        return 1
    fi

}

#--- Upload to remote host ---
if [ "$UPLOAD_CUSTOM_ISO" = "true" ]; then
    log "INFO" "Upload enabled, preparing to upload to ESXi host..."

    # Validate SSH target
    if ! validate_ssh_target; then
        log_error "SSH validation failed. Skipping upload."
        log "INFO" "Custom ISO available locally at: ${custom_iso_path}"
        exit 1
    fi

    log "INFO" "Uploading to VMware ESXi host ${VMWARE_SSH_HOST_CONFIG}..."
    log_verbose "Upload path: ${VMWARE_ISO_UPLOAD_PATH}"

    # Upload checksum file
    log "INFO" "Uploading checksum file..."
    scp "${custom_iso_checksum_file}" "${VMWARE_SSH_HOST_CONFIG}:${VMWARE_ISO_UPLOAD_PATH}/" || {
        log_error "Failed to upload checksum file!"
        exit 1
    }
    log_verbose "✓ Checksum uploaded"

    # Upload ISO file
    log "INFO" "Uploading custom ISO (this may take a while)..."
    scp "${custom_iso_path}" "${VMWARE_SSH_HOST_CONFIG}:${VMWARE_ISO_UPLOAD_PATH}/" || {
        log_error "Failed to upload custom ISO!"
        exit 1
    }

    log_success "✓ Upload complete"
    log "INFO" "Remote location: ${VMWARE_SSH_HOST_CONFIG}:${VMWARE_ISO_UPLOAD_PATH}/${custom_iso_name}"

    # TODO: Verify checksum on remote host (LATER USE)
    # ssh ${VMWARE_SSH_HOST_CONFIG} "sha256sum ${VMWARE_ISO_UPLOAD_PATH}/${custom_iso_name}"
else
    log "INFO" "Upload disabled (UPLOAD_CUSTOM_ISO=false)"
    log "INFO" "Custom ISO available locally at: ${custom_iso_path}"
fi

#--- Cleanup ---
if [ "$KEEP_WORKING_DIRECTORY" = "true" ]; then
    log "INFO" "Keeping working directory (KEEP_WORKING_DIRECTORY=true)"
    log_verbose "Working directory: ${working_dir_path}"
else
    if [[ -d "${working_dir_path}" ]]; then
        log "INFO" "Cleaning up working directory..."
        rm -rf "${working_dir_path}"
        log_verbose "✓ Working directory removed"
    else
        log_verbose "Working directory not found, nothing to clean"
    fi
fi

#--- Summary ---
log_success "==================================="
log_success "Custom ISO Builder completed successfully!"
log_success "==================================="
log "INFO" "Local ISO: ${custom_iso_path}"
if [ "$UPLOAD_CUSTOM_ISO" = "true" ]; then
    log "INFO" "Remote ISO: ${VMWARE_SSH_HOST_CONFIG}:${VMWARE_ISO_UPLOAD_PATH}/${custom_iso_name}"
fi
log "INFO" "Build completed at $(date '+%Y-%m-%d %H:%M:%S')"

# exit 0

# End of script
