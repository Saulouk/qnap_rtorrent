#!/bin/sh
# Alias for 20-configure-rutorrent-ui.sh (download picker + plugins).

set -e
exec sh "$(dirname "$0")/20-configure-rutorrent-ui.sh" "$@"
