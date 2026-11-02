# ISOs

No file table here — ISO contents are git-ignored. This directory only explains the layout.

| Subfolder | Purpose |
| --- | --- |
| `Source/` | downloaded upstream ISOs (cache) — re-download only with `OVERRIDE_EXISTING_SOURCE_ISO=true` |
| `Custom/` | generated custom ISOs + checksum (SHA256 value in a `.md5`-named file — see TODOs) |
| `Valid/` | manually validated ISOs |

The builder downloads a missing source ISO automatically (`create-iso.sh`, fetch-if-missing).
For discovering and downloading new upstream images (e.g. a new Ubuntu release), use
`scripts/iso-catalog.sh` — see main README → Usage.
