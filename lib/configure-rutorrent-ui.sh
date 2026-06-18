#!/bin/sh
# Full ruTorrent UI: download directory picker + plugins + lighttpd iframe headers.

apply_rutorrent_ui_config() {
    rut_web="$1"
    rut_conf_dir="${rut_web}/conf"

    . "${RECOVERY_ROOT}/lib/configure-rutorrent-downloads.sh"
    . "${RECOVERY_ROOT}/lib/configure-rutorrent-plugins.sh"

    download_block="$(rutorrent_php_externals_block | sed "s|DATA_ROOT_SLASH_PLACEHOLDER|${DATA_ROOT_SLASH}|g")"

    for cfg in "${rut_conf_dir}/config.php" "${rut_conf_dir}/users/"*/config.php; do
        [ -f "$cfg" ] || continue
        if grep -q 'topDirectory' "$cfg" 2>/dev/null; then
            sed -i "s|\$topDirectory = .*|\$topDirectory = '${DATA_ROOT_SLASH}';|" "$cfg"
        else
            sed -i "/^<?php/a\\
${download_block}" "$cfg"
        fi
        if ! grep -q 'pathToExternals' "$cfg" 2>/dev/null; then
            sed -i "/^<?php/a\\
${download_block}" "$cfg"
        fi
    done

    apply_rutorrent_download_ui "$rut_conf_dir"
    write_rutorrent_plugins_ini "$rut_conf_dir" "$rut_web"
    clear_rutorrent_plugin_cache
    rutorrent_init_plugins "$rut_web"
}

restart_lighttpd_if_configured() {
  lighttpd_conf="${ENTWARE_ROOT}/lighttpd.conf"
  [ -f "$lighttpd_conf" ] || return 0
  . "${RECOVERY_ROOT}/lib/start-lighttpd.sh"
  lighttpd_bin=""
  for b in /opt/sbin/lighttpd /opt/bin/lighttpd; do
      [ -x "$b" ] && lighttpd_bin="$b" && break
  done
  php_cgi=""
  for p in /opt/bin/php-cgi /opt/bin/php8-cgi /opt/bin/php; do
      [ -x "$p" ] && php_cgi="$p" && break
  done
  [ -n "$lighttpd_bin" ] && [ -n "$php_cgi" ] || return 0

  if ! grep -q 'mod_setenv' "$lighttpd_conf" 2>/dev/null; then
      log "Patching lighttpd.conf for X-Frame-Options (folder picker iframe)..."
      sed -i 's/"mod_scgi"/"mod_scgi", "mod_setenv"/' "$lighttpd_conf" 2>/dev/null || true
      if ! grep -q 'X-Frame-Options' "$lighttpd_conf" 2>/dev/null; then
          sed -i '/auth.backend.htpasswd.userfile/a\
setenv.add-response-header = (\
  "X-Frame-Options" => "SAMEORIGIN"\
)' "$lighttpd_conf" 2>/dev/null || true
      fi
  fi

  start_lighttpd_stack "$lighttpd_conf" "$lighttpd_bin" "$php_cgi" || \
      log "WARN: lighttpd restart failed — run: sh scripts/19-finish-multiuser-webui.sh"
}

find_rutorrent_web() {
    for candidate in \
        "${ENTWARE_ROOT}/www/rutorrent" \
        /opt/share/rutorrent \
        /opt/www/rutorrent \
        /opt/share/www/rutorrent; do
        if [ -f "${candidate}/conf/config.php" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}
