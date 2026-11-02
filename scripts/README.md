# Scripts

| Script | Purpose |
| --- | --- |
| `docker-entrypoint.sh` | container entrypoint — SSH key setup (config/env modes), then runs `create-iso.sh`; honors `ISO_BUILDER_KEEP_ALIVE` |
| `iso-catalog.sh` *(planned)* | query Debian/Ubuntu download directories, download to `ISOs/Source` with checksum verify, scaffold a config in `configs/available/` — see TODOs |
