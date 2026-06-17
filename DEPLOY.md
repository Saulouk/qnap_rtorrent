# Deploy recovery toolkit to QNAP NAS

## Option A: SMB (Windows)

1. Open `\\192.168.1.2\Public` in Explorer (or your NAS IP).
2. Copy the entire `qnap-rtorrent-recovery` folder into `Public`.
3. SSH in and run:

```sh
chmod +x /share/Public/qnap-rtorrent-recovery/*.sh
chmod +x /share/Public/qnap-rtorrent-recovery/scripts/*.sh
cd /share/Public/qnap-rtorrent-recovery
./00-run-all.sh
```

## Option B: Paste via SSH

```sh
mkdir -p /share/Public/qnap-rtorrent-recovery
cd /share/Public/qnap-rtorrent-recovery
# Then upload files via WinSCP or cat/heredoc each script
```

## Before full import

1. Review inventory report after step 1:
   `/share/Public/rtorrent-debug-backup/inventory-*/INVENTORY_REPORT.txt`
2. Edit path mappings if download folders moved:
   `/share/Public/qnap-rtorrent-recovery/path-map.conf`
3. Run test import (10 torrents), verify in UI, then:
   `sh scripts/06-batch-import.sh 100`

## If Entware is not installed

App Center → Install Manually → Entware std qpkg  
Wiki: https://github.com/Entware/Entware/wiki/Install-on-QNAP-NAS

Then add to `~/.profile`:
```sh
source /opt/etc/profile
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `opkg: not found` | Install/start Entware QPKG |
| SCGI timeout | Check `entware/logs/rtorrent.err` |
| getplugins error | Ensure `conf/access.ini` exists (step 5 creates it) |
| Wrong save paths | Edit `path-map.conf`, re-import batch |
| Port 6010 in use | Change `WEB_PORT` in `lib/common.sh` |

## Root cause (your NAS)

The old rtorrent-Pro binary crashes with `epoll_ctl Operation not permitted` on QTS 5 ARMv7 even with empty session. Entware provides a separately built rtorrent that avoids the broken QPKG binary/libs.
