#!/bin/bash
set -e

# Docker entrypoint script for ISO builder
# Handles SSH credential setup and environment preparation

#--- SSH Setup Function ---
setup_ssh_credentials() {
    local ssh_mode="${SSH_MODE:-auto}"
    # Create universal symlink for ANY user (isobuilder OR root)
    SSH_APP_MOUNT="/app/.ssh"
    SSH_LINK_TARGET="${HOME}/.ssh"
    
    echo "======================"
    echo "[ENTRYPOINT] SSH_APP_MOUNT: ${SSH_APP_MOUNT}"
    echo "[ENTRYPOINT] SSH_LINK_TARGET: ${SSH_LINK_TARGET}"
    echo "======================"

    echo "[ENTRYPOINT] SSH Mode: $ssh_mode"
    
    # Auto-detect mode if not specified
    if [ "$ssh_mode" = "auto" ]; then
        if [[ -d "${SSH_APP_MOUNT}" ]] && [[ "${SSH_APP_MOUNT}"/config* ]]; then
            ssh_mode="config"
            echo "[ENTRYPOINT] Auto-detected SSH mode: config (mounted)"
        else
            ssh_mode="env"
            echo "[ENTRYPOINT] Auto-detected SSH mode: env (CI/CD)"
        fi
    fi
    
    echo "[ENTRYPOINT] SSH Mode2: $ssh_mode"

    if [ "$ssh_mode" = "env" ]; then
        echo "[ENTRYPOINT] Setting up SSH credentials from environment variables..."
        
        # Ensure .ssh directory exists with correct permissions
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        
        # Decode and write private key if provided
        if [ -n "$VMWARE_SSH_PRIVATE_KEY_BASE64" ]; then
            echo "[ENTRYPOINT] Writing SSH private key..."
            echo "$VMWARE_SSH_PRIVATE_KEY_BASE64" | base64 -d > "$HOME/.ssh/id_rsa"
            chmod 600 "$HOME/.ssh/id_rsa"
        else
            echo "[ENTRYPOINT] WARNING: No SSH private key provided (VMWARE_SSH_PRIVATE_KEY_BASE64)"
        fi
        
        # Setup known_hosts if provided
        if [ -n "$VMWARE_SSH_KNOWN_HOSTS_ENTRY" ]; then
            echo "[ENTRYPOINT] Writing SSH known_hosts..."
            echo "$VMWARE_SSH_KNOWN_HOSTS_ENTRY" | base64 -d > "$HOME/.ssh/known_hosts"
            chmod 644 "$HOME/.ssh/known_hosts"
        fi
        
        # Variables are already in environment from docker-compose env_file
        # No need to source .env file

        # Generate SSH config if we have the necessary variables
        if [ -n "$VMWARE_SSH_HOST_CONFIG" ] && [ -n "$VMWARE_SSH_HOST" ] && [ -n "$VMWARE_SSH_USER" ]; then
            echo "[ENTRYPOINT] Generating SSH config..."
            cat > "$HOME/.ssh/config" <<SSHCONFIG
Host ${VMWARE_SSH_HOST_CONFIG}
    HostName ${VMWARE_SSH_HOST}
    User ${VMWARE_SSH_USER}
    Port ${VMWARE_SSH_PORT:-22}
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking ${VMWARE_SSH_STRICT_HOST_CHECKING:-no}
    UserKnownHostsFile ~/.ssh/known_hosts
SSHCONFIG
            chmod 600 "$HOME/.ssh/config"
            echo "[ENTRYPOINT] SSH configuration generated successfully"
        else
            echo "[ENTRYPOINT] WARNING: Insufficient SSH configuration variables"
            echo "  VMWARE_SSH_HOST_CONFIG=${VMWARE_SSH_HOST_CONFIG:-<not set>}"
            echo "  VMWARE_SSH_HOST=${VMWARE_SSH_HOST:-<not set>}"
            echo "  VMWARE_SSH_USER=${VMWARE_SSH_USER:-<not set>}"
        fi
    else
        # we are in ssh Config mode
        # Remove old symlink if exists
        [ -L "${SSH_LINK_TARGET}" ] && rm "${SSH_LINK_TARGET}"
        echo "========= WTF 00 =========="
        # Create symlink to mounted SSH
        ln -s "${SSH_APP_MOUNT}" "${HOME}"
        # chmod 700 "${SSH_LINK_TARGET}"
        ls "${SSH_LINK_TARGET}"
        echo "[ENTRYPOINT] ✓ SSH symlink created: ${SSH_LINK_TARGET} → /app/.ssh"
        echo "========= WTF 00 =========="

        echo "[ENTRYPOINT] Using existing SSH configuration from mounted ~/.ssh"
        
        # Verify SSH config exists
        if [ ! -f "$HOME/.ssh/config" ]; then
            echo "[ENTRYPOINT] WARNING: No SSH config found at $HOME/.ssh/config"
        fi
    fi
    
    # Display SSH configuration status
    if [ -f "$HOME/.ssh/config" ]; then
        echo "[ENTRYPOINT] ✓ SSH config file exists"
    fi
    
    if [ -f "$HOME/.ssh/id_rsa" ] || [ -f "$HOME/.ssh/id_ed25519" ]; then
        echo "[ENTRYPOINT] ✓ SSH private key found"
    fi
}

#--- Verify Required Directories ---
verify_directories() {
    echo "[ENTRYPOINT] Verifying directory structure..."
    
    local required_dirs=("/app/configs" "/app/preseeds" "/app/ISOs")
    local missing=false
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "[ENTRYPOINT] ERROR: Required directory not found: $dir"
            missing=true
        else
            echo "[ENTRYPOINT] ✓ $dir"
        fi
    done
    
    if [ "$missing" = "true" ]; then
        echo "[ENTRYPOINT] ERROR: Missing required directories. Check volume mounts."
        exit 1
    fi
}

#--- Verify Environment Variables ---
verify_env_vars() {
    # Check if critical environment variables are set (loaded from .env via env_file)
    if [ -z "$VMWARE_SSH_HOST_CONFIG" ]; then
        echo "[ENTRYPOINT] WARNING: VMWARE_SSH_HOST_CONFIG not set"
        echo "[ENTRYPOINT] Upload functionality may not work"
    else
        echo "[ENTRYPOINT] ✓ Environment variables loaded from .env"
    fi
}

#--- Main Entrypoint Logic ---
main() {
    echo "==========================================="
    echo "Custom ISO Builder - Docker Container"
    echo "Version: 0.2.0"
    echo "==========================================="
    echo ""

    # Run verification checks
    verify_directories
    verify_env_vars
    
    # Setup SSH credentials
    setup_ssh_credentials
    
    echo ""
    echo "==========================================="
    echo "Container initialization complete"
    echo "==========================================="
    echo ""
    
    # Execute the command passed to the container
    if [ $# -eq 0 ]; then
        echo "[ENTRYPOINT] No command provided, using default: /app/create-iso.sh"
        # ALWAYS run the script first, THEN keep alive
        echo "[ENTRYPOINT] Running main script..."
        # Call the script with sudo, could not find a better way to run with elevated permissions as non-root user
        # -> User isobuilder has limited sudo rights scoped to /app/create-iso.sh only.
        # isobuilder user -> use sudo
        # sudo -E /app/create-iso.sh || echo "Script failed but keeping container alive"
        # root user -> no sudo
        sudo -E /app/create-iso.sh || echo "Script failed but keeping container alive"
        # TODO: Add option to not keep alive after script completion KEEP_ALIVE=true|false
        if [ "${ISO_BUILDER_KEEP_ALIVE}" = "true" ]; then
            echo "[ENTRYPOINT] ISO_BUILDER_KEEP_ALIVE is true - keeping container alive after script completion"
            echo "[ENTRYPOINT] Script complete - keeping container alive for inspection..."
            exec tail -f /dev/null
        else
            echo "[ENTRYPOINT] ISO_BUILDER_KEEP_ALIVE is false - exiting container after script completion"
            echo "[ENTRYPOINT] Script complete - exiting container."
            exit 0
        fi
    else
        echo "[ENTRYPOINT] Executing command: $*"
        exec "$@"
    fi
}

# Run main function
main
