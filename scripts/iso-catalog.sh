#!/usr/bin/env bash
# ============================================================
# iso-catalog.sh — ISO discovery, download & config scaffolder
# ============================================================
# Queries upstream Debian/Ubuntu download directories, lets you pick
# an image, downloads it to ISOs/Source (checksum-verified) and
# scaffolds a ready config in configs/templates/.
#
# The catalog cache (configs/catalog/catalog.yml) is a plain list and
# is meant to be COMMITTED — regenerate with --update-cache, then commit.
# It also carries a 'nomenclature' section (URL & ISO-name matrix per
# distro) used to validate existing configs (--check-configs).
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
#   --check-configs   validate iso_url / iso_checksum / iso names of every cfg
#                     in configs/available/ and configs/build/ (live checks)
#   --no-interactive  fail instead of prompting (requires --version and --flavor)
#   --dry-run         show what would be done: no download, no scaffold written
#   -h | --help       this help
#
# Examples — how to DOWNLOAD an ISO:
#   scripts/iso-catalog.sh ubuntu                          # interactive: pick version+flavor, confirm, download
#   scripts/iso-catalog.sh ubuntu --version 26.10 --flavor live-server   # direct download
#   scripts/iso-catalog.sh ubuntu --list                   # just show what exists upstream
#   scripts/iso-catalog.sh debian --check-configs          # validate all cfg URLs
#
# Distro specifics (URL/ISO-name rules, scaffold bodies) live in data files:
#   scripts/scaffolds/<distro>.spec + scripts/scaffolds/<distro>.scaffold
#
# Requirements: bash, curl. Works on macOS and in the Debian container.
CATALOG_VERSION="0.0.3"
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
info() { echo "[catalog] $*" >&2; }
warn() { echo "[catalog] WARNING: $*" >&2; }

reverse_lines() { awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}'; }

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
    echo "# ISO catalog cache — generated by scripts/iso-catalog.sh v${CATALOG_VERSION}. List only, safe to commit."
    echo "# Do not edit manually. Regenerate with: scripts/iso-catalog.sh ubuntu --update-cache"
    echo "# Updated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
    echo "# URL & ISO-name nomenclature matrix — mirror of the URL builders in"
    echo "# scripts/iso-catalog.sh; used as reference by --check-configs."
    echo "nomenclature:"
    echo "  ubuntu:"
    echo "    iso_name: ubuntu-{version}-{flavor}-{arch}.iso"
    echo "    iso_url: https://releases.ubuntu.com/{version}/{iso_name}"
    echo "    checksum_url: https://releases.ubuntu.com/{version}/SHA256SUMS (SHA256)"
    echo "    flavors: live-server, desktop"
    echo "  debian:"
    echo "    netinst:"
    echo "      iso_name: debian-{version}-{arch}-netinst.iso"
    echo "      iso_url: https://cdimage.debian.org/cdimage/archive/{version}/{arch}/iso-cd/{iso_name}"
    echo "      checksum_url: https://cdimage.debian.org/cdimage/archive/{version}/{arch}/iso-cd/SHA512SUMS (SHA512)"
    echo "    dvd:"
    echo "      iso_name: debian-{version}-{arch}-DVD-1.iso"
    echo "      iso_url: https://cdimage.debian.org/cdimage/archive/{version}/{arch}/iso-dvd/{iso_name}"
    echo "      checksum_url: https://cdimage.debian.org/cdimage/archive/{version}/{arch}/iso-dvd/SHA512SUMS (SHA512)"
    echo ""
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

# --- distro resolution & scaffolding (data-driven via scripts/scaffolds/) --
# Per-distro specifics live in scripts/scaffolds/<distro>.spec (URL/ISO-name
# rules + output path) and scripts/scaffolds/<distro>.scaffold (config body
# with __TOKEN__ placeholders). Adding a distro (e.g. Rocky) = add a
# scrape function + a spec/scaffold pair — the engine below stays untouched.
resolve_distro() { # <distro> <version> <flavor> <arch>
  # sets caller-visible: ISO_NAME, ISO_URL, SUMS_URL, ALGO, OUT
  local spec="${SCRIPT_DIR}/scaffolds/${1}.spec"
  [[ -f "$spec" ]] || { warn "no scaffold spec for '${1}' (${spec})"; return 1; }
  local VERSION="$2" FLAVOR="$3" ARCH="$4" SC_SUBDIR=""
  # shellcheck disable=SC1090
  source "$spec"
  [[ -n "${ISO_NAME:-}" && -n "${ISO_URL:-}" && -n "${OUT:-}" ]] || { warn "spec ${spec} did not set ISO_NAME/ISO_URL/OUT"; return 1; }
}

scaffold() { # <distro> <version> <codename> <flavor> <arch> <write|dry> -> echoes OUT
  local distro="$1" version="$2" codename="$3" flavor="$4" arch="$5" mode="$6"
  local body="${SCRIPT_DIR}/scaffolds/${distro}.scaffold" rendered choice
  [[ -f "$body" ]] || die "no scaffold body for '${distro}' (${body})"
  resolve_distro "$distro" "$version" "$flavor" "$arch" || die "cannot resolve ${distro} ${version}/${flavor}"
  rendered=$(mktemp)
  sed -e "s|__VERSION__|${version}|g" -e "s|__CODENAME__|${codename}|g" -e "s|__ARCH__|${arch}|g" \
      -e "s|__FLAVOR__|${flavor}|g" -e "s|__ISO_NAME__|${ISO_NAME}|g" -e "s|__ISO_URL__|${ISO_URL}|g" \
      -e "s|__SUMS_URL__|${SUMS_URL}|g" "$body" > "$rendered"
  if [[ -f "$OUT" ]]; then
    if cmp -s "$rendered" "$OUT"; then
      info "existing template matches scaffold — keeping: ${OUT}"
    elif [[ "$mode" == "dry" ]]; then
      info "existing template differs from scaffold: ${OUT}"
    elif ! $NO_INTERACTIVE; then
      choice=$(ask "Template exists and differs — (r)eplace or (k)eep?" "k")
      if [[ "$choice" =~ ^[Rr] ]]; then
        cp "$rendered" "$OUT"; info "replaced: ${OUT}"
      else
        info "keeping existing: ${OUT}"
      fi
    else
      warn "existing template differs from scaffold — keeping existing (non-interactive): ${OUT}"
    fi
  else
    if [[ "$mode" == "dry" ]]; then
      info "--dry-run: scaffold not written (would be: ${OUT})"
    else
      cp "$rendered" "$OUT"; info "scaffold written: ${OUT}"
    fi
  fi
  rm -f "$rendered"
  echo "$OUT"
}

# --- download & verify -----------------------------------------------------
file_size() { # portable stat (macOS/BSD + GNU)
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
}

progress_bar() { # <url> <dest> — curl silent + our own rectangle bar (█)
  local url="$1" dest="$2" expected pid rc size pct filled empty bar width=40
  expected=$(curl -fsSIL --max-time 20 "$url" 2>/dev/null \
    | awk 'tolower($1)=="content-length:" { s=$2 } END { print s+0 }' \
    | tail -1)
  # run curl quietly in the background
  curl -fL --retry 3 -sS -o "$dest" "$url" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    size=$(file_size "$dest")
    if [[ "$expected" -gt 0 ]]; then
      pct=$(( size * 100 / expected ))
      filled=$(( size * width / expected )); (( filled > width )) && filled=$width
      printf -v bar '%*s' "$filled" ''; bar=${bar// /█}
      printf -v empty '%*s' $(( width - filled )) ''
      printf '\r[%s%s] %3d%% (%s / %s bytes)' "$bar" "$empty" "$pct" "$size" "$expected"
    else
      printf '\r%s bytes (size unknown)' "$size"
    fi
    sleep 0.5
  done
  wait "$pid" && rc=0 || rc=$?
  if [[ "$expected" -gt 0 ]]; then
    printf -v bar '%*s' "$width" ''; bar=${bar// /█}
    printf '\r[%s] 100%% (%s bytes)\n' "$bar" "$expected"
  else
    printf '\r%s bytes (size unknown)\n' "$(file_size "$dest")"
  fi
  [[ "$rc" -eq 0 ]] || die "download failed (curl exit ${rc}): $url"
}

download_and_verify() { # <url> <iso_name> <sums_url> <algo 256|512>
  local url="$1" iso="$2" sums_url="$3" algo="$4" tool sums_line
  mkdir -p "$SOURCE_DIR"
  info "downloading ${iso} ..."
  progress_bar "$url" "${SOURCE_DIR}/${iso}.part"
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

# --- config validation ------------------------------------------------------
check_configs() { # validate iso_url / iso_checksum / iso names of every cfg (live checks)
  local cfg vals os ver arch iso url sums flavor subdir expected url_st sum_st nom_st local_st any_fail=false
  local -a cfgs=()
  for cfg in "${ROOT_DIR}"/configs/available/*.cfg "${ROOT_DIR}"/configs/build/*.cfg; do
    [[ -f "$cfg" ]] && cfgs+=("$(basename "$cfg")|$cfg")
  done
  [[ ${#cfgs[@]} -gt 0 ]] || die "no cfg files found in configs/available/ or configs/build/"
  echo "# validating ${#cfgs[@]} config(s) — live URL checks (nomenclature matrix: ${CACHE_FILE})"
  printf '%-44s %-14s %-38s %-10s %-11s %-9s %s\n' "CONFIG" "DISTRO/VER" "ISO" "URL" "CHECKSUM" "NOMENC" "LOCAL"
  for cfg in "${cfgs[@]}"; do
    cfg_path="${cfg#*|}"
    # source like create-iso.sh does (trusted repo files) to expand ${...} references
    vals=$( set +u; source "$cfg_path" 2>/dev/null; \
      printf '%s|%s|%s|%s|%s|%s' "${linux_os_type:-}" "${debian_version:-}" "${debian_arch:-}" "${debian_iso_name:-}" "${iso_url:-}" "${iso_checksum:-}" ) || true
    IFS='|' read -r os ver arch iso url sums <<< "$vals"

    # URL check (follows redirects like cdimage mirrors)
    if [[ -z "$url" ]]; then
      url_st="NOT-SET"; any_fail=true
    else
      code=$(curl -fsSI -L -o /dev/null -w '%{http_code}' --max-time 20 "$url" 2>/dev/null || echo "000")
      if [[ "$code" == "200" ]]; then url_st="OK"; else url_st="FAIL($code)"; any_fail=true; fi
    fi

    # checksum URL check: reachable AND contains an entry for the ISO name
    if [[ -z "$sums" ]]; then
      sum_st="not-set"
    else
      if curl -fsSL --max-time 20 "$sums" 2>/dev/null \
        | awk -v f="$iso" '{ n=$2; if (substr(n,1,1)=="*") n=substr(n,2); if (n==f) found=1 } END { exit !found }'; then
        sum_st="OK"
      else
        sum_st="FAIL"; any_fail=true
      fi
    fi

    # nomenclature: does iso_url match the expected matrix for this distro/version/flavor?
    nom_st="-"
    if [[ -n "$url" && -n "$iso" ]]; then
      local dfl=""
      if [[ "$os" == "ubuntu" ]]; then
        dfl=$(echo "$iso" | sed -E "s/^ubuntu-${ver}-(.+)-${arch}\.iso\$/\\1/")
      elif [[ "$os" == "debian" ]]; then
        [[ "$iso" == *"DVD-1.iso" ]] && dfl="dvd" || dfl="netinst"
      fi
      ISO_NAME=""; ISO_URL=""; SUMS_URL=""; ALGO=""; OUT=""
      if resolve_distro "$os" "$ver" "$dfl" "$arch"; then
        [[ "$ISO_URL" == "$url" ]] && nom_st="match" || nom_st="drift"
      else
        nom_st="no-spec"
      fi
    fi

    if [[ -n "$iso" && -f "${SOURCE_DIR}/${iso}" ]]; then local_st="cached"; else local_st="-"; fi
    printf '%-44s %-14s %-38s %-10s %-11s %-9s %s\n' "$(basename "$cfg_path")" "${os}/${ver}" "$iso" "$url_st" "$sum_st" "$nom_st" "$local_st"
  done
  echo ""
  echo "legend: URL/CHECKSUM FAIL = broken link (fix the cfg) · NOMENC drift = URL works but does not"
  echo "        follow the catalog nomenclature matrix · CHECKSUM not-set = iso_checksum empty in cfg"
  $any_fail && die "one or more configs have broken URLs/checksums"
  info "all configs valid"
  exit 0
}

# --- argument parsing ------------------------------------------------------
show_help() { sed -n '/^# Usage:/,/^# Requirements/p' "$0" | sed 's/^# \{0,1\}//'; }

DISTRO="" UPDATE_CACHE=false OVERRIDE=false NO_INTERACTIVE=false DRY_RUN=false LIST_ONLY=false CHECK_CONFIGS=false
SEL_VERSION="" SEL_FLAVOR="" SEL_ARCH="amd64"
[[ $# -ge 1 ]] || { show_help; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    debian|ubuntu) DISTRO="$1" ;;
    --update-cache) UPDATE_CACHE=true ;;
    --override) OVERRIDE=true ;;
    --no-interactive) NO_INTERACTIVE=true ;;
    --dry-run) DRY_RUN=true ;;
    --list) LIST_ONLY=true ;;
    --check-configs) CHECK_CONFIGS=true ;;
    --version) shift; [[ $# -ge 1 ]] || die "--version needs a value"; SEL_VERSION="$1" ;;
    --flavor) shift; [[ $# -ge 1 ]] || die "--flavor needs a value"; SEL_FLAVOR="$1" ;;
    --arch) shift; [[ $# -ge 1 ]] || die "--arch needs a value"; SEL_ARCH="$1" ;;
    -h|--help) show_help; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done
command -v curl >/dev/null 2>&1 || die "curl is required"
info "iso-catalog v${CATALOG_VERSION}"

if $CHECK_CONFIGS; then
  check_configs   # always exits
fi
[[ -n "$DISTRO" ]] || die "distro required: debian or ubuntu (or use --check-configs)"

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
  echo "# distro: ${DISTRO}  (iso-catalog v${CATALOG_VERSION}, catalog: ${CACHE_FILE}) — newest first"
  printf '%-12s %-10s %-28s %s\n' "VERSION" "CODENAME" "FLAVORS" "ARCHS"
  echo "$ENTRIES" | reverse_lines | while IFS= read -r e; do
    IFS='|' read -r v c f a <<< "$e"
    printf '%-12s %-10s %-28s %s\n' "$v" "$c" "$f" "$a"
  done
  echo ""
  echo "to download an ISO:" 
  echo "  $0 ${DISTRO}                                          # interactive: pick, confirm, download"
  echo "  $0 ${DISTRO} --version <version> --flavor <flavor>    # direct download"
  exit 0
fi

# version selection (displayed newest-first; 'latest' = first line)
if [[ -z "$SEL_VERSION" ]]; then
  $NO_INTERACTIVE && die "--no-interactive requires --version and --flavor"
  echo "Available ${DISTRO} versions (newest first):"
  echo "$ENTRIES" | reverse_lines | awk -F'|' '{printf "  %2d) %-12s %-10s %s\n", NR, $1, $2, $3}'
  SEL_VERSION=$(ask "Select version (number or exact version)" "latest")
fi
if [[ "$SEL_VERSION" == "latest" ]]; then
  SEL_VERSION=$(echo "$ENTRIES" | reverse_lines | head -1 | cut -d'|' -f1)
elif [[ "$SEL_VERSION" =~ ^[0-9]+$ ]]; then
  SEL_VERSION=$(echo "$ENTRIES" | reverse_lines | sed -n "${SEL_VERSION}p" | cut -d'|' -f1) || true
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

# resolve ISO details + scaffold (data-driven: scripts/scaffolds/<distro>.spec/.scaffold)
ISO_NAME=""; ISO_URL=""; SUMS_URL=""; ALGO=""; OUT=""
resolve_distro "$DISTRO" "$VERSION" "$SEL_FLAVOR" "$SEL_ARCH" \
  || die "cannot resolve ${DISTRO} ${VERSION}/${SEL_FLAVOR} (missing scripts/scaffolds/${DISTRO}.spec?)"
CFG_OUT=$(scaffold "$DISTRO" "$VERSION" "$CODENAME" "$SEL_FLAVOR" "$SEL_ARCH" "$($DRY_RUN && echo dry || echo write)")

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

# explicit confirmation before any download (skipped with --no-interactive)
if ! $NO_INTERACTIVE; then
  confirm "Proceed with download to ISOs/Source?" "y" \
    || { info "aborted — nothing downloaded (scaffold kept: ${CFG_OUT})"; exit 0; }
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
