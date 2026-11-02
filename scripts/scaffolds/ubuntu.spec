# iso-catalog scaffold spec — Ubuntu
# Sourced by scripts/iso-catalog.sh (resolve_distro).
# Engine provides: VERSION, FLAVOR, ARCH, ROOT_DIR.
# Spec must set: ISO_NAME, ISO_URL, SUMS_URL, ALGO, OUT
ISO_NAME="ubuntu-${VERSION}-${FLAVOR}-${ARCH}.iso"
ISO_URL="https://releases.ubuntu.com/${VERSION}/${ISO_NAME}"
SUMS_URL="https://releases.ubuntu.com/${VERSION}/SHA256SUMS"
ALGO=256
OUT="${ROOT_DIR}/configs/templates/ubuntu-${VERSION}-${FLAVOR}-example.conf"
