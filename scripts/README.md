# Scripts

| Script | Purpose |
| --- | --- |
| `docker-entrypoint.sh` | container entrypoint — SSH key setup (config/env modes), then runs `create-iso.sh`; honors `ISO_BUILDER_KEEP_ALIVE` |
| `iso-catalog.sh` (v0.0.3) | query Debian/Ubuntu download directories (`--list`, newest first), download to `ISOs/Source` with rectangle progress bar + checksum verify, scaffold a config in `configs/templates/`, validate cfg URLs (`--check-configs`); cache + nomenclature matrix in `configs/catalog/catalog.yml` (committed); see main README → Usage |
| `scaffolds/<distro>.spec` + `.scaffold` | data files for iso-catalog: URL/ISO-name rules + output path (spec) and config body with `__TOKEN__` placeholders (scaffold). Adding a distro (e.g. Rocky) = add a scrape function in the script + a spec/scaffold pair here |
