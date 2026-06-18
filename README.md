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

Edit `path-map.conf` before import if download paths changed between QTS 4 and 5.

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
