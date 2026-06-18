# QNAP rtorrent Recovery (ARMv7 / QTS 5)

Native Entware-based replacement for broken rtorrent-Pro QPKG. Preserves old torrents and paths.

## Quick start (on NAS via SSH)

```sh
cd /share/Public
# Copy this folder to the NAS (SMB, scp, or paste files), then:
chmod +x qnap-rtorrent-recovery/*.sh
cd qnap-rtorrent-recovery
./00-run-all.sh
```

Or run steps individually:

| Step | Script | Purpose |
|------|--------|---------|
| 1 | `01-backup-inventory.sh` | Backup + inventory old session/settings |
| 2 | `02-entware-check.sh` | Verify Entware and package availability |
| 3 | `03-install-entware-rtorrent.sh` | Install rtorrent + ruTorrent stack |
| 4 | `04-minimal-native-test.sh` | Prove SCGI/XMLRPC works |
| 5 | `05-configure-rutorrent.sh` | Web UI on port 6010 |
| 6 | `06-batch-import.sh` | Import old torrents with path mapping |
| 7 | `07-disable-old-qpkg.sh` | Stop broken rtorrent-Pro package |
| optional | `08-find-torrent-data.sh` | Locate old `.torrent`/session files if import finds none |
| optional | `09-retarget-by-existing-data.sh` | Point imported torrents at existing NAS data |
| optional | `10-rewrite-directory-prefix.sh` | Replace temporary download root while preserving subfolders |
| optional | `11-import-with-existing-paths.sh` | Import old `.torrent` files directly against existing NAS paths |

## Ports

| Service | Port | Notes |
|---------|------|-------|
| Old QPKG | 6009 | Disable after migration |
| New ruTorrent | 6010 | Entware lighttpd |
| rtorrent SCGI | 19010 | Entware instance |

## Data locations

| Path | Role |
|------|------|
| `/share/Rdownload/session.disabled-debug` | Old session (do not delete) |
| `/share/Rdownload/entware/` | New Entware rtorrent data |
| `/share/Public/rtorrent-debug-backup/` | Recovery backups |

## Path mapping

Edit `path-roots.conf` before validation if download paths changed between QTS 4 and 5.

Typical QTS 4 layout:

| Old path | New path |
|----------|----------|
| `/share/Rdownload/downloads/SN/Movies` | `/share/SN/Movies` |
| `/share/SN Drive/Torrents/...` | unchanged |

Only the `/share/Rdownload/downloads/SN` prefix is rewritten to `/share/SN`.
Paths under `/share/SN Drive/` are not transformed.

## If import finds zero torrents

Run:

```sh
sh scripts/08-find-torrent-data.sh
```

Then inspect the generated `/share/Public/rtorrent-debug-backup/torrent-data-search-*.txt`
report. The old rtorrent-Pro QPKG may have stored the real `.torrent` or session
metadata outside `/share/Rdownload/session.disabled-debug`.

## If imported torrents point at `/share/Rdownload/entware/downloads`

Stop them and retarget by matching torrent names to existing files/directories:

```sh
sh scripts/09-retarget-by-existing-data.sh
```

Review `/share/Public/rtorrent-debug-backup/retarget-*.tsv`. If matches look
correct, apply them:

```sh
sh scripts/09-retarget-by-existing-data.sh apply /share/CACHEDEV1_DATA/Rdownload/downloads /share/CACHEDEV1_DATA/Rdownload/complete /share/CACHEDEV1_DATA/Rdownload
```

The script calls `d.directory.set` and then `d.check_hash` so rtorrent verifies
existing data instead of redownloading into the new Entware folder.

If the imported torrents already have useful subpaths under the temporary
Entware download root, rewrite only the prefix:

```sh
sh scripts/10-rewrite-directory-prefix.sh /share/SN
sh scripts/10-rewrite-directory-prefix.sh apply /share/SN
```

Example: `/share/Rdownload/entware/downloads/Movies` becomes `/share/SN/Movies`.

If the current rtorrent session is empty, import from the recovered `.torrent`
backup and infer paths by matching torrent names to existing data under
`/share/SN`:

```sh
sh scripts/11-import-with-existing-paths.sh /share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720 /share/SN 20
sh scripts/11-import-with-existing-paths.sh apply /share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720 /share/SN 20
```

This preserves category subfolders because it sets the torrent directory to the
parent folder where the matching file/directory already exists.

## Historic path recovery (recommended)

Recover original per-torrent save paths from old session/sidecar backups, then
rewrite only the storage root to `/share/SN` while keeping subfolders like
`Movies`, `Drama Series`, and `Software`.

```sh
chmod +x 12-run-historic-recovery.sh scripts/12-*.sh scripts/13-*.sh scripts/14-*.sh scripts/15-*.sh scripts/16-*.sh
sh 12-run-historic-recovery.sh
```

Or step by step:

| Step | Script | Purpose |
|------|--------|---------|
| 12 | `12-freeze-current.sh` | Stop active torrents; disable watch auto-import |
| 13 | `13-find-path-sources.sh` | Inventory session.bak*, sidecars, settings, tar backups |
| 14 | `14-extract-historic-paths.sh` | Bencode + strings extraction; filesystem fallback |
| 15 | `15-validate-historic-paths.sh` | Transform roots via `path-roots.conf`; verify data exists |
| 16 | `16-apply-historic-paths.sh` | `d.directory.set` + `d.check_hash` (batch then all) |

Review `/share/Public/rtorrent-debug-backup/historic-path-map-validated-latest.tsv`
before applying. Edit `path-roots.conf` if your old root differed from the defaults.

```sh
# Dry-run first 5 OK rows
sh scripts/16-apply-historic-paths.sh

# Apply small batch, verify in ruTorrent
sh scripts/16-apply-historic-paths.sh apply 5

# Apply all validated paths and remove wrong partial downloads
sh scripts/16-apply-historic-paths.sh apply-all cleanup
```

To unfreeze watch imports after migration:

```sh
sh scripts/12-freeze-current.sh unfreeze
```
