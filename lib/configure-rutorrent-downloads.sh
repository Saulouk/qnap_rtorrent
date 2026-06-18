#!/bin/sh
# ruTorrent download directory UI: topDirectory, rtorrent default path.

rutorrent_php_externals_block() {
    cat <<'PHPEOF'
	$topDirectory = 'DATA_ROOT_SLASH_PLACEHOLDER';
	$pathToExternals = array(
		"php"  => '/opt/bin/php8-cli',
		"curl" => '/opt/bin/curl',
		"gzip" => '/opt/bin/gzip',
		"id"   => '/opt/bin/id',
		"stat" => '/opt/bin/stat',
	);
PHPEOF
}

patch_rtorrent_conf_download_root() {
    conf="$1"
    [ -f "$conf" ] || return 0
    if grep -q '^directory.default.set' "$conf" 2>/dev/null; then
        sed -i "s|^directory.default.set.*|directory.default.set = ${DATA_ROOT}|" "$conf"
    else
        printf '\ndirectory.default.set = %s\n' "$DATA_ROOT" >> "$conf"
    fi
}

rpc_set_default_directory() {
    socket="$1"
    php_bin="/opt/bin/php8-cli"
    [ -x "$php_bin" ] || php_bin="/opt/bin/php"
    [ -x "$php_bin" ] || return 0
    [ -S "$socket" ] || return 0
    RTORRENT_SCGI_SOCKET="$socket" "$php_bin" "${RECOVERY_ROOT}/lib/rtorrent-rpc.php" \
        directory.default.set "$DATA_ROOT" >/dev/null 2>&1 || true
}

ensure_download_root_visible() {
    mkdir -p "$DATA_ROOT"
    chmod 777 "$DATA_ROOT" 2>/dev/null || true
}

apply_rutorrent_download_ui() {
    rut_conf_dir="$1"
    ensure_download_root_visible
    patch_rtorrent_conf_download_root "$SAULOUK_RUT_CONF"
    patch_rtorrent_conf_download_root "$JOSH_RUT_CONF"
    patch_rtorrent_conf_download_root "${ENTWARE_RUT_CONF}"
    rpc_set_default_directory "$SAULOUK_SOCKET"
    rpc_set_default_directory "$JOSH_SOCKET"
    rpc_set_default_directory "$SCGI_SOCKET"
    log "Download UI root: ${DATA_ROOT_SLASH}"
}
