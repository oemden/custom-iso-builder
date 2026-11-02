# Preseeds & Autoinstall Files

Debian preseeds (`.cfg`) and Ubuntu autoinstall files (`.yml`) baked into custom ISOs.
See main README → [Section 4: Preseed / Autoinstall Files](../README.md#4-preseed--autoinstall-files)
for usage, the `private/` vault and password generation.

- Root files: tracked, shareable (sanitized)
- `private/`: git-ignored vault — real hostnames / users / password hashes, never committed
- `templates/`: tracked starting points

## Files

| File | Distro / Flavor | Version | Delta vs stock |
| --- | --- | --- | --- |
| `preseed_debian-12.cfg` | debian | 12 (bookworm) | early simple preseed, no cloud-init |
| `preseed_debian-13.1.0.cfg` | debian | 13.1.0 (trixie) | v0.0.2, packer4-derived; pkgsel already includes cloud-init |
| `preseed_debian-cloudinit-12.9.0.cfg` | debian | 12.9.0 ⚠ | **stale copy** — byte-identical to `preseed_debian-13.1.0.cfg`, header still says trixie; needs review |
| `preseed_debian-cloudinit-13.1.0.cfg` | debian | 13.1.0 | vs `preseed_debian-13.1.0.cfg`: one comment line only — needs review |
| `autoinstall_ubuntu-24.04.3.yml` | ubuntu / live-server | 24.04.3 | first-generation standard autoinstall (pre-flavor split) |
| `autoinstall_ubuntu-24.04.3-live-server.yml` | ubuntu / live-server | 24.04.3 | standard; DHCP netplan network block active |
| `autoinstall_ubuntu-25.10-live-server.yml` | ubuntu / live-server | 25.10 | network block disabled (static IP + cloud-init vmware guestinfo datasource tests) |
| `autoinstall_ubuntu-25.10-live-server-latest-kernel.yml` | ubuntu / live-server | 25.10 | late-commands: mainline kernel **6.18.7** via cappelikan PPA (`mainline install`), + `policykit-1` |
| `private/autoinstall_ubuntu-24.04.3-desktop.yml` | ubuntu / desktop | 24.04.3 | USB key / baremetal; `user-data` real account, `identity:` disabled (never worked with cloud-init) |
| `private/autoinstall_ubuntu-25.10-desktop.yml` | ubuntu / desktop | 25.10 | same as 24.04.3 desktop variant, updated |
| `private/autoinstall_ubuntu-25.10-desktop-template.yml` | ubuntu / desktop | 25.10 | template with `identity:` placeholder (dummy password) |
| `templates/preseed_debian-13.1.0-template.cfg` | debian | 13.1.0 | template, no secrets |

⚠ = name/purpose mismatch flagged for review (see TODOs).

## Naming convention

- Debian: `preseed_debian-<version>[-cloudinit].cfg`
- Ubuntu: `autoinstall_ubuntu-<version>[-<type>][-latest-kernel].yml`
- Templates: `-template` suffix
