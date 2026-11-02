# Configs

OS build configurations — declare which source ISO to download, which preseed/autoinstall
file to bake in, and the custom ISO name. See main README →
[Section 3: OS Configuration](../README.md#3-os-configuration).

- `available/` — your library of ready configs (table below)
- `build/` — **the trigger**: exactly ONE file here = one build; the script errors on more
- `templates/` — example configs to start from
- `custom-iso-builder.cfg` — global builder options (upload toggle, overrides; main README Section 2)

## `available/` files

| File | OS | Version | Flavor | Preseed / autoinstall referenced | Output comment |
| --- | --- | --- | --- | --- | --- |
| `debian-13.1.0.cfg` | debian | 13.1.0 | DVD-1 | `preseed_debian-13.1.0.cfg` | `CloudInitReady` |
| `debian-cloudinit-12.9.0.cfg` | debian | 12.9.0 | netinst | `preseed_debian-cloudinit-12.9.0.cfg` | `CloudInitReady` |
| `debian-cloudinit-13.1.0.cfg` | debian | 13.1.0 | DVD-1 | `preseed_debian-13.1.0.cfg` | `CloudInitTest` |
| `ubuntu-24.04.3.cfg` | ubuntu | 24.04.3 | live-server | `autoinstall_ubuntu-24.04.3.yml` | `vmware_tests` |
| `ubuntu-25.10.cfg` | ubuntu | 25.10 | live-server | `autoinstall_ubuntu-25.10.yml` | `vmware_tests` |
| `ubuntu-25.10-live-server.cfg` | ubuntu | 25.10 | live-server | `autoinstall_ubuntu-25.10-live-server.yml` | `vmware_tests` |
| `ubuntu-25.10-desktop.cfg` | ubuntu | 25.10 | desktop | `private/autoinstall_ubuntu-25.10-desktop.yml` | `baremetal` |

## `build/` (active)

| File | Notes |
| --- | --- |
| `ubuntu-25.10-live-server-latest-kernel.cfg` | currently active — produces `ubuntu-25.10-live-server-amd64-latest-kernel-0.0.1.iso` |
