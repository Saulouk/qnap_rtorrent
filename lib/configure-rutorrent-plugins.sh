#!/bin/sh
# ruTorrent plugin defaults — scan installed plugins, enable a sensible set.

# Space-separated plugin folder names to force off (security / conflicts).
# loginmgr is intentionally not disabled; rutracker_check depends on it.
RUTORRENT_PLUGINS_DISABLE="httprpc xmpp _cloudflare"

# Prefer enabled=yes when present on disk. Any other installed plugin is also
# enabled below, so this list mainly controls ordering for core plugins.
RUTORRENT_PLUGINS_ENABLE="_getdir _task _noty theme datadir create edit erasedata source ratio rss scheduler tracklabels throttle geoip show_peers_like_wtorrent chunks diskspace check_port autotools feeds rssurlrewrite extratio retrackers history trafic cpuload data screenshots seedingtime unpack lookat mediainfo bulk_magnet uploadeta spectrogram trackerstatus extsearch filedrop dump ipad rutracker_check log_history seedbox cookies"

plugin_list_contains() {
    needle="$1"
    shift
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

write_rutorrent_plugins_ini() {
    conf_dir="$1"
    rut_web="$2"
    plugins_dir="${rut_web}/plugins"

    mkdir -p "$conf_dir"
    {
        echo "; ruTorrent plugin permissions — generated $(date '+%Y-%m-%d %H:%M:%S')"
        echo "[default]"
        echo "enabled = user-defined"
        echo "canChangeToolbar = yes"
        echo "canChangeMenu = yes"
        echo "canChangeOptions = yes"
        echo "canChangeTabs = yes"
        echo "canChangeColumns = yes"
        echo "canChangeStatusBar = yes"
        echo "canChangeCategory = yes"
        echo "canBeShutdowned = yes"
        echo ""

        if [ -d "$plugins_dir" ]; then
            for plug in $RUTORRENT_PLUGINS_DISABLE; do
                [ -d "${plugins_dir}/${plug}" ] || continue
                echo "[${plug}]"
                echo "enabled = no"
                echo ""
            done
            for plug in $RUTORRENT_PLUGINS_ENABLE; do
                [ -d "${plugins_dir}/${plug}" ] || continue
                echo "[${plug}]"
                echo "enabled = yes"
                echo ""
            done
            for path in "${plugins_dir}"/*; do
                [ -d "$path" ] || continue
                plug="$(basename "$path")"
                plugin_list_contains "$plug" $RUTORRENT_PLUGINS_DISABLE && continue
                plugin_list_contains "$plug" $RUTORRENT_PLUGINS_ENABLE && continue
                echo "[${plug}]"
                echo "enabled = yes"
                echo ""
            done
        fi
    } > "${conf_dir}/plugins.ini"
}

clear_rutorrent_plugin_cache() {
    find "${ENTWARE_ROOT}/users" -name 'plugins.dat' 2>/dev/null | while read -r f; do
        rm -f "$f"
        log "Cleared plugin cache: $f"
    done
    [ -f "${ENTWARE_ROOT}/settings/plugins.dat" ] && rm -f "${ENTWARE_ROOT}/settings/plugins.dat"
}

rutorrent_init_plugins() {
    rut_web="$1"
    php_bin="/opt/bin/php8-cli"
    [ -x "$php_bin" ] || php_bin="/opt/bin/php"
    [ -x "$php_bin" ] || return 0
    [ -f "${rut_web}/php/initplugins.php" ] || return 0

    for user in "$USER_SAULOUK_RPC" "$USER_JOSH_RPC"; do
        log "initplugins.php ${user}"
        (cd "${rut_web}/php" && "$php_bin" initplugins.php "$user") 2>/dev/null || true
    done
}

apply_rutorrent_plugins() {
    conf_dir="$1"
    rut_web="$2"
    write_rutorrent_plugins_ini "$conf_dir" "$rut_web"
    clear_rutorrent_plugin_cache
    rutorrent_init_plugins "$rut_web"
    enabled_count="$(grep -c '^enabled = yes' "${conf_dir}/plugins.ini" 2>/dev/null || echo 0)"
    log "ruTorrent plugins: ${enabled_count} enabled in plugins.ini"
}
