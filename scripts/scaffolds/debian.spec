# iso-catalog scaffold spec — Debian
# Sourced by scripts/iso-catalog.sh (resolve_distro).
# Engine provides: VERSION, FLAVOR, ARCH, ROOT_DIR.
# Spec must set: ISO_NAME, ISO_URL, SUMS_URL, ALGO, OUT
case "${FLAVOR}" in
  dvd) SC_SUBDIR="iso-dvd"; ISO_NAME="debian-${VERSION}-${ARCH}-DVD-1.iso" ;;
  *)   SC_SUBDIR="iso-cd";  ISO_NAME="debian-${VERSION}-${ARCH}-netinst.iso" ;;
esac
ISO_URL="https://cdimage.debian.org/cdimage/archive/${VERSION}/${ARCH}/${SC_SUBDIR}/${ISO_NAME}"
SUMS_URL="https://cdimage.debian.org/cdimage/archive/${VERSION}/${ARCH}/${SC_SUBDIR}/SHA512SUMS"
ALGO=512
OUT="${ROOT_DIR}/configs/templates/debian-${VERSION}-example.cfg"
