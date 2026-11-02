#!/usr/bin/env bash
# ============================================================
# iso-catalog.sh — ISO discovery, download & config scaffolder
# ============================================================
# Queries upstream Debian/Ubuntu download directories, lets you pick
# an image, downloads it to ISOs/Source (checksum-verified) and
# scaffolds a ready config in configs/available/.
#
# The catalog cache (configs/catalog/catalog.yml) is a plain list and
# is meant to be COMMITTED — regenerate with --update-cache, then commit.
#
# Not part of create-iso.sh: it stays a discovery tool. create-iso.sh
# already downloads missing source ISOs at build time.
#
# Usage:
#   scripts/iso-catalog.sh <debian|ubuntu> [options]
#
#   --update-cache    regenerate the catalog cache (both distros), then continue
#   --override        re-download even if the ISO already exists in ISOs/Source
#                     (default comes from OVERRIDE_EXISTING_SOURCE_ISO in
#                     configs/custom-iso-builder.cfg)
#   --version <v>     preselect version (skips prompt)
#   --flavor <f>      preselect flavor: live-server|desktop (ubuntu),
#                     netinst|dvd (debian)
#   --arch <a>        preselect arch (default: amd64)
#   --list            print the catalog for the distro and exit
#   --no-interactive  fail instead of prompting (requires --version and --flavor)
#   --dry-run         show what would be done: no download, no scaffold written
#   -h | --help       this help
#
# Requirements: bash, curl. Works on macOS and in the Debian container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
CACHE_FILE="${ROOT_DIR}/configs/catalog/catalog.yml"
SOURCE_DIR="${ROOT_DIR}/ISOs/Source"
BUILDER_CFG="${ROOT_DIR}/configs/custom-iso-builder.cfg"

UBUNTU_INDEX="https://releases.ubuntu.com/"
DEBIAN_INDEX="https://cdimage.debian.org/cdimage/archive/"

# Fallback codename maps (primary sources: page <title> for Ubuntu,
# major version for Debian). Extend as new releases land.
UBUNTU_CODENAMES=(
  "24.04:noble" "24.10:oracular" "25.04:plucky" "25.10:questing"
  "26.04:resolute" "26.10:stonking"
)
DEBIAN_CODENAMES=("8:jessie" "9:stretch" "10:buster" "11:bullseye" "12:bookworm" "13:trixie" "14:forky")
# Debian: only keep supported-ish majors in the cache (bullseye and newer)
DEBIAN_MIN_MAJOR=11

# --- helpers ---------------------------------------------------------------
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[catalog] $*"; }
warn() { echo "[catalog] WARNING: $*" >&2; }

ask() { # ask <prompt> <default> -> answer on stdout
  local prompt="$1" default="$2" answer
  read -r -p "${prompt} [${default}]: " answer || die "input closed"
  echo "${answer:-$default}"
}

confirm() { # confirm <prompt> <default yes|no>
  local prompt="$1" default="$2" answer
  read -r -p "${prompt} ${default} " answer || die "input closed"
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

sha_tool() { # sha_tool <256|512> -> tool + args for checksum verification
  if command -v "sha${1}sum" >/dev/null 2>&1; then
    echo "sha${1}sum -c -"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a ${1} -c -"
  else
    die "no checksum tool found (need sha${1}sum or shasum)"
  fi
}

codename_for_ubuntu() { # from major.minor, fallback map
  local mm="${1%%.*}.$(echo "$1" | cut -d. -f2)" entry
  for entry in "${UBUNTU_CODENAMES[@]}"; do
    [[ "${entry%%:*}" == "$mm" ]] && { echo "${entry##*:}"; return 0; }
  done
  return 1
}

codename_for_debian() { # from major
  local major="${1%%.*}" entry
  for entry in "${DEBIAN_CODENAMES[@]}"; do
    [[ "${entry%%:*}" == "$major" ]] && { echo "${entry##*:}"; return 0; }
  done
  return 1
}

# --- cache -----------------------------------------------------------------
# Format (restricted YAML, generated AND parsed by this script only — do not
# hand-edit):
#   ubuntu:
#     - version: "26.10"
#       codename: stonking
#       flavors: live-server, desktop
#       archs: amd64
cache_read() { # cache_read <distro> -> lines "version|codename|flavors|archs"
  [[ -f "$CACHE_FILE" ]] || return 1
  awk -v distro="$1" '
    /^[a-z]+:$/ { current = substr($0, 1, length($0) - 1); next }
    current != distro { next }
    /^  - version:/ { v = $3; gsub(/"/, "", v); next }
    /^    codename:/ { c = $2; next }
    /^    flavors:/ { sub(/^    flavors: */, ""); f = $0; next }
    /^    archs:/ { sub(/^    archs: */, ""); a = $0; print v "|" c "|" f "|" a }
  ' "$CACHE_FILE"
}

scrape_ubuntu_entries() { # -> lines "version|codename|flavors|archs"
  local index_html versions v dir_html codename flavors archs
  index_html=$(curl -fsSL --max-time 30 "$UBUNTU_INDEX") || die "cannot fetch $UBUNTU_INDEX"
  # version dirs only (X.Y or X.Y.Z[.W]); skip codename dirs (bionic/, focal/…)
  versions=$(echo "$index_html" \
    | grep -oE 'href="[0-9]+(\.[0-9]+)+/"' \
    | sed 's/href="//; s/\/"//' | sort -uV)
  # tidy: drop bare X.Y entries when a X.Y.Z sibling exists
  versions=$(echo "$index_html" \
    | grep -oE 'href="[0-9]+(\.[0-9]+)+/"' | sed 's/href="//; s/\/"//' | sort -uV \
    | awk -F. '{key=$1"."$2; if (NF==2) bare[key]=$0; else full[key]=$0}
      END { for (k in bare) if (!(k in full)) print bare[k]
            for (k in full) print full[k] }' | sort -V)
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue
    dir_html=$(curl -fsSL --max-time 30 "${UBUNTU_INDEX}${v}/") || { warn "cannot list ${UBUNTU_INDEX}${v}/ — skipped"; continue; }
    # codename from the page title: "Ubuntu 26.10 (Stonking Stingray)"
    # only trusted when the title version matches the dir (guards against
    # upstream redirects, e.g. 24.04.5.1/ redirects to the latest release page)
    title=$(echo "$dir_html" | grep -oE '<title>[^<]+</title>' | head -1)
    title_version=$(echo "$title" | sed -E 's/<title>Ubuntu ([0-9.]+).*/\1/')
    codename=""
    if [[ "$title_version" == "$v" ]]; then
      codename=$(echo "$title" | sed -E 's/.*\(([A-Za-z]+) [A-Za-z]+\)<\/title>/\1/' | tr '[:upper:]' '[:lower:]')
      [[ "$codename" =~ ^[a-z]+$ ]] || codename=""
    fi
    [[ -z "$codename" ]] && codename=$(codename_for_ubuntu "$v" || echo "")
    [[ -z "$codename" ]] && { warn "no codename for Ubuntu $v — add it to UBUNTU_CODENAMES in the script"; codename="unknown"; }
    # flavors/archs from iso filenames: ubuntu-<version>-<flavor>-<arch>.iso
    # (flavor may be multi-word, e.g. live-server; skip beta builds)
    isos=$(echo "$dir_html" | grep -oE "href=\"ubuntu-${v}-[a-z0-9-]+\.iso\"" \
      | sed "s/href=\"//; s/\"//; s/^ubuntu-${v}-//; s/\.iso\$//" | grep -v '^beta' | sort -u)
    flavors=$(echo "$isos" | sed 's/-[^-]*$//' | sort -u | paste -sd, -)
    archs=$(echo "$isos" | sed 's/.*-//' | sort -u | paste -sd, -)
    [[ -z "$flavors" ]] && { warn "no ISOs found for Ubuntu $v — skipped"; continue; }
    echo "${v}|${codename}|${flavors}|${archs}"
  done <<< "$versions"
}

scrape_debian_entries() { # -> lines "version|codename|flavors|archs"
  local index_html versions v codename
  index_html=$(curl -fsSL --max-time 30 "$DEBIAN_INDEX") || die "cannot fetch $DEBIAN_INDEX"
  # modern version dirs only (X.Y.Z); skips old 3.0_r0 style entries
  versions=$(echo "$index_html" \
    | grep -oE 'href="[0-9]+\.[0-9]+\.[0-9]+/"' \
    | sed 's/href="//; s/\/"//' | sort -uV \
    | awk -F. -v min="${DEBIAN_MIN_MAJOR}" '$1 >= min')
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue
    codename=$(codename_for_debian "$v" || echo "")
    [[ -z "$codename" ]] && { warn "no codename for Debian $v (add to DEBIAN_CODENAMES map)"; codename="unknown"; }
    # flavors follow the fixed cdimage nomenclature (verified at download time)
    echo "${v}|${codename}|netinst,dvd|amd64"
  done <<< "$versions"
}

cache_write() { # regenerates the whole cache file (both distros)
  local tmp entries
  tmp=$(mktemp)
  {
    echo "# ISO catalog cache — generated by scripts/iso-catalog.sh. List only, safe to commit."
    echo "# Do not edit manually. Regenerate with: scripts/iso-catalog.sh ubuntu --update-cache"
    echo "# Updated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
    echo "ubuntu:"
    entries=$(scrape_ubuntu_entries)
    [[ -z "$entries" ]] && die "ubuntu scrape produced no entries"
    while IFS= read -r e; do
      IFS='|' read -r v c f a <<< "$e"
      printf '  - version: "%s"\n    codename: %s\n    flavors: %s\n    archs: %s\n' "$v" "$c" "$f" "$a"
    done <<< "$entries"
    echo ""
    echo "debian:"
    entries=$(scrape_debian_entries)
    [[ -z "$entries" ]] && die "debian scrape produced no entries"
    while IFS= read -r e; do
      IFS='|' read -r v c f a <<< "$e"
      printf '  - version: "%s"\n    codename: %s\n    flavors: %s\n    archs: %s\n' "$v" "$c" "$f" "$a"
    done <<< "$entries"
  } > "$tmp"
  mkdir -p "$(dirname "$CACHE_FILE")"
  mv "$tmp" "$CACHE_FILE"
  info "cache written: ${CACHE_FILE}"
}

# --- URL construction (nomenclature, verified at download time) ------------
ubuntu_iso_url()   { echo "${UBUNTU_INDEX}${1}/ubuntu-${1}-${2}-${3}.iso"; }
ubuntu_sums_url()  { echo "${UBUNTU_INDEX}${1}/SHA256SUMS"; }          # algo 256
debian_dvd()       { echo "debian-${1}-amd64-DVD-1.iso"; }
debian_netinst()   { echo "debian-${1}-amd64-netinst.iso"; }
debian_iso_url()   { echo "${DEBIAN_INDEX}${1}/amd64/${2}/${3}"; }     # $2: iso-dvd|iso-cd
debian_sums_url()  { echo "${DEBIAN_INDEX}${1}/amd64/${2}/SHA512SUMS"; } # algo 512

# --- download & verify -----------------------------------------------------
download_and_verify() { # <url> <iso_name> <sums_url> <algo 256|512>
  local url="$1" iso="$2" sums_url="$3" algo="$4" tool sums_line
  mkdir -p "$SOURCE_DIR"
  info "downloading ${iso} ..."
  curl -fL --retry 3 --progress-bar -o "${SOURCE_DIR}/${iso}.part" "$url" \
    || die "download failed: $url"
  info "verifying checksum (SHA${algo}) ..."
  # checksum lines: "<hash>  file" (debian) or "<hash> *file" (ubuntu) — normalize both
  sums_line=$(curl -fsSL --max-time 30 "$sums_url" \
    | awk -v f="$iso" '{ n=$2; if (substr(n,1,1)=="*") n=substr(n,2); if (n==f) print $1 "  " f ".part" }')
  [[ -n "$sums_line" ]] || { rm -f "${SOURCE_DIR}/${iso}.part"; die "no checksum entry for ${iso} in ${sums_url}"; }
  tool=$(sha_tool "$algo")
  (cd "$SOURCE_DIR" && echo "$sums_line" | $tool) \
    || { rm -f "${SOURCE_DIR}/${iso}.part"; die "checksum FAILED for ${iso} — re-run with --override"; }
  mv "${SOURCE_DIR}/${iso}.part" "${SOURCE_DIR}/${iso}"
  info "checksum OK: ${SOURCE_DIR}/${iso}"
}

# --- config scaffolding ----------------------------------------------------
scaffold_ubuntu() { # <version> <codename> <flavor> <arch> [write] -> cfg path (written unless "write" != write)
  local v="$1" c="$2" flavor="$3" arch="$4" mode="${5:-write}" tpl out
  tpl="${ROOT_DIR}/configs/templates/ubuntu-25.10-example.cfg"
  [[ -f "$tpl" ]] || die "template not found: $tpl"
  out="${ROOT_DIR}/configs/available/ubuntu-${v}-${flavor}.cfg"
  [[ "$mode" == "write" ]] || { echo "$out"; return 0; }
  [[ -f "$out" ]] && die "config already exists: $out (edit it manually instead)"
  sed \
    -e "s|^debian_version=.*|debian_version=\"${v}\"|" \
    -e "s|^debian_codename=.*|debian_codename=\"${c}\"|" \
    -e "s|^debian_arch=.*|debian_arch=\"${arch}\"|" \
    -e "s|^debian_iso_name=.*|debian_iso_name=\"ubuntu-${v}-${flavor}-${arch}.iso\"|" \
    -e "s|^# iso_url=.*||" \
    -e "s|^iso_url=.*|iso_url=\"$(ubuntu_iso_url "$v" "$flavor" "$arch")\"|" \
    -e "s|^# iso_checksum=\"\".*|iso_checksum=\"$(ubuntu_sums_url "$v")\"|" \
    -e "s|^config_file=.*|config_file=\"ubuntu-${v}-${flavor}.cfg\"|" \
    -e "s|autoinstall_ubuntu-\${debian_version}|autoinstall_ubuntu-\${debian_version}-${flavor}|g" \
    -e "s|^custom_iso_version=.*|custom_iso_version=\"0.0.1\"|" \
    -e "s|^custom_iso_comment=.*|custom_iso_comment=\"catalog\"|" \
    -e "s|^custom_iso_name=.*|custom_iso_name=\"ubuntu-${v}-${flavor}-${arch}-\${custom_iso_comment}-\${custom_iso_version}.iso\"|" \
    "$tpl" > "$out"
  echo "$out"
}

scaffold_debian() { # <version> <codename> <flavor> [write] -> cfg path (written unless 4th arg given)
  local v="$1" c="$2" flavor="$3" mode="${4:-write}" arch="amd64" subdir iso tpl out
  tpl="${ROOT_DIR}/configs/templates/debian-13.1.0-example.cfg"
  [[ -f "$tpl" ]] || die "template not found: $tpl"
  out="${ROOT_DIR}/configs/available/debian-${v}.cfg"
  [[ "$mode" == "write" ]] || { echo "$out"; return 0; }
  [[ -f "$out" ]] && die "config already exists: $out (edit it manually instead)"
  if [[ "$flavor" == "dvd" ]]; then subdir="iso-dvd"; iso=$(debian_dvd "$v")
  else subdir="iso-cd"; iso=$(debian_netinst "$v"); fi
  sed \
    -e "s|^debian_version=.*|debian_version=\"${v}\"|" \
    -e "s|^debian_codename=.*|debian_codename=\"${c}\"|" \
    -e "s|^debian_arch=.*|debian_arch=\"${arch}\"|" \
    -e "s|^debian_iso_name=.*|debian_iso_name=\"${iso}\"|" \
    -e "s|^iso_url=.*|iso_url=\"$(debian_iso_url "$v" "$subdir" "$iso")\"|" \
    -e "s|^iso_checksum=.*|iso_checksum=\"$(debian_sums_url "$v" "$subdir")\"|" \
    -e "s|^config_file=.*|config_file=\"debian-${v}.cfg\"|" \
    -e "s|^custom_iso_version=.*|custom_iso_version=\"0.0.1\"|" \
    -e "s|^custom_iso_comment=.*|custom_iso_comment=\"catalog\"|" \
    -e "s|^custom_iso_name=.*|custom_iso_name=\"debian-${v}-${arch}-\${custom_iso_comment}-\${custom_iso_version}.iso\"|" \
    "$tpl" > "$out"
  echo "$out"
}

# --- argument parsing ------------------------------------------------------
DISTRO="" UPDATE_CACHE=false OVERRIDE=false NO_INTERACTIVE=false DRY_RUN=false LIST_ONLY=false
SEL_VERSION="" SEL_FLAVOR="" SEL_ARCH="amd64"
[[ $# -ge 1 ]] || { grep '^# Usage' -A 20 "$0" | sed 's/^# \{0,1\}//'; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    debian|ubuntu) DISTRO="$1" ;;
    --update-cache) UPDATE_CACHE=true ;;
    --override) OVERRIDE=true ;;
    --no-interactive) NO_INTERACTIVE=true ;;
    --dry-run) DRY_RUN=true ;;
    --list) LIST_ONLY=true ;;
    --version) shift; [[ $# -ge 1 ]] || die "--version needs a value"; SEL_VERSION="$1" ;;
    --flavor) shift; [[ $# -ge 1 ]] || die "--flavor needs a value"; SEL_FLAVOR="$1" ;;
    --arch) shift; [[ $# -ge 1 ]] || die "--arch needs a value"; SEL_ARCH="$1" ;;
    -h|--help) grep '^# Usage' -A 20 "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done
[[ -n "$DISTRO" ]] || die "distro required: debian or ubuntu"
command -v curl >/dev/null 2>&1 || die "curl is required"

# --- main ------------------------------------------------------------------
if $UPDATE_CACHE; then
  cache_write
elif [[ ! -f "$CACHE_FILE" ]]; then
  info "no cache found — building it (this only lists upstream directories)"
  cache_write
  info "tip: the cache file is meant to be committed — it is only a list"
else
  info "using cache: ${CACHE_FILE}"
  if ! $NO_INTERACTIVE && ! $LIST_ONLY; then
    confirm "Update cache first?" "n" && cache_write
  fi
fi

ENTRIES=$(cache_read "$DISTRO") || die "no '${DISTRO}:' section in cache — run with --update-cache"

if $LIST_ONLY; then
  echo "# distro: ${DISTRO}  (catalog: ${CACHE_FILE})"
  printf '%-12s %-10s %-28s %s\n' "VERSION" "CODENAME" "FLAVORS" "ARCHS"
  while IFS= read -r e; do
    IFS='|' read -r v c f a <<< "$e"
    printf '%-12s %-10s %-28s %s\n' "$v" "$c" "$f" "$a"
  done <<< "$ENTRIES"
  exit 0
fi

# version selection
if [[ -z "$SEL_VERSION" ]]; then
  $NO_INTERACTIVE && die "--no-interactive requires --version and --flavor"
  echo "Available ${DISTRO} versions (newest last):"
  echo "$ENTRIES" | awk -F'|' '{printf "  %2d) %-12s %-10s %s\n", NR, $1, $2, $3}'
  SEL_VERSION=$(ask "Select version (number or exact version)" "latest")
fi
if [[ "$SEL_VERSION" == "latest" ]]; then
  SEL_VERSION=$(echo "$ENTRIES" | tail -1 | cut -d'|' -f1)
elif [[ "$SEL_VERSION" =~ ^[0-9]+$ ]]; then
  SEL_VERSION=$(echo "$ENTRIES" | sed -n "${SEL_VERSION}p" | cut -d'|' -f1) || true
  [[ -n "$SEL_VERSION" ]] || die "invalid selection"
fi
ENTRY=$(echo "$ENTRIES" | grep -E "^${SEL_VERSION//./\\.}\|" | head -1)
[[ -n "$ENTRY" ]] || die "version '${SEL_VERSION}' not in catalog (try --update-cache)"
IFS='|' read -r VERSION CODENAME FLAVORS ARCHS <<< "$ENTRY"

# flavor selection
if [[ -z "$SEL_FLAVOR" ]]; then
  $NO_INTERACTIVE && die "--no-interactive requires --version and --flavor"
  echo "Flavors for ${DISTRO} ${VERSION}: $(echo "$FLAVORS" | tr ',' ' ')"
  SEL_FLAVOR=$(ask "Select flavor" "$(echo "$FLAVORS" | cut -d, -f1)")
fi
echo "$FLAVORS" | tr ',' '\n' | grep -qx "$SEL_FLAVOR" \
  || die "flavor '${SEL_FLAVOR}' not available for ${VERSION} (have: ${FLAVORS})"

# arch selection (skip prompt when only one)
if [[ "$ARCHS" != *","* ]]; then
  SEL_ARCH="$ARCHS"
elif [[ -z "$SEL_ARCH" ]]; then
  $NO_INTERACTIVE && die "--no-interactive requires --arch (available: ${ARCHS})"
  echo "Archs: $(echo "$ARCHS" | tr ',' ' ')"
  SEL_ARCH=$(ask "Select arch" "amd64")
fi
echo "$ARCHS" | tr ',' '\n' | grep -qx "$SEL_ARCH" \
  || die "arch '${SEL_ARCH}' not available for ${VERSION} (have: ${ARCHS})"

# resolve ISO details
if [[ "$DISTRO" == "ubuntu" ]]; then
  ISO_NAME="ubuntu-${VERSION}-${SEL_FLAVOR}-${SEL_ARCH}.iso"
  ISO_URL=$(ubuntu_iso_url "$VERSION" "$SEL_FLAVOR" "$SEL_ARCH")
  SUMS_URL=$(ubuntu_sums_url "$VERSION"); ALGO=256
  CFG_OUT=$(scaffold_ubuntu "$VERSION" "$CODENAME" "$SEL_FLAVOR" "$SEL_ARCH" "$($DRY_RUN && echo dry || echo write)")
else
  if [[ "$SEL_FLAVOR" == "dvd" ]]; then
    SUBDIR="iso-dvd"; ISO_NAME=$(debian_dvd "$VERSION")
  else
    SUBDIR="iso-cd"; ISO_NAME=$(debian_netinst "$VERSION")
  fi
  ISO_URL=$(debian_iso_url "$VERSION" "$SUBDIR" "$ISO_NAME")
  SUMS_URL=$(debian_sums_url "$VERSION" "$SUBDIR"); ALGO=512
  CFG_OUT=$(scaffold_debian "$VERSION" "$CODENAME" "$SEL_FLAVOR" "$($DRY_RUN && echo dry || echo write)")
fi

# default override behavior from builder cfg (same semantics as create-iso.sh)
if ! $OVERRIDE && [[ -f "$BUILDER_CFG" ]]; then
  grep -q '^OVERRIDE_EXISTING_SOURCE_ISO=true' "$BUILDER_CFG" && OVERRIDE=true
fi

echo "-------"
info "distro    : ${DISTRO} ${VERSION} (${CODENAME})"
info "iso       : ${ISO_NAME}"
info "url       : ${ISO_URL}"
info "checksum  : ${SUMS_URL} (SHA${ALGO})"
info "config    : ${CFG_OUT}"

if $DRY_RUN; then
  info "--dry-run: no download, config scaffold not written (would be: ${CFG_OUT})"
  exit 0
fi

if [[ -f "${SOURCE_DIR}/${ISO_NAME}" ]] && ! $OVERRIDE; then
  info "ISO already present in ISOs/Source — skipping download (use --override to force)"
else
  [[ -f "${SOURCE_DIR}/${ISO_NAME}" ]] && info "override: re-downloading over existing file"
  download_and_verify "$ISO_URL" "$ISO_NAME" "$SUMS_URL" "$ALGO"
fi

PRESEED_HINT="preseeds/templates/"
[[ "$DISTRO" == "ubuntu" ]] && PRESEED_HINT="preseeds/templates/ or preseeds/private/ (see preseeds/README.md)"

echo "-------"
info "done."
echo "next steps:"
echo "  1. create/point the preseed or autoinstall file referenced by the config (start from ${PRESEED_HINT})"
echo "  2. cp ${CFG_OUT} configs/build/   (exactly one file — this triggers the build)"
echo "  3. docker-compose up  (or sudo ./create-iso.sh)"
