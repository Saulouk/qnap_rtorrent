#!/bin/sh
# Full ruTorrent UI: download directory picker + plugins + lighttpd iframe headers.

apply_rutorrent_ui_config() {
    rut_web="$1"
    rut_conf_dir="${rut_web}/conf"

    . "${RECOVERY_ROOT}/lib/configure-rutorrent-downloads.sh"
    . "${RECOVERY_ROOT}/lib/configure-rutorrent-plugins.sh"

    ensure_rutorrent_plugins_installed "$rut_web"

    for cfg in "${rut_conf_dir}/config.php" "${rut_conf_dir}/users/"*/config.php; do
        [ -f "$cfg" ] || continue
        rewrite_rutorrent_config "$cfg"
    done

    apply_rutorrent_download_ui "$rut_conf_dir"
    write_rutorrent_plugins_ini "$rut_conf_dir" "$rut_web"
    clear_rutorrent_plugin_cache
    rutorrent_init_plugins "$rut_web"
}

rewrite_rutorrent_config() {
    cfg="$1"
    tmp="${cfg}.tmp.$$"

    awk -v top="${DATA_ROOT_SLASH}" '
        /^<\?php/ {
            print
            print "\t$topDirectory = '\''" top "'\'';"
            print "\t$pathToExternals = array("
            print "\t\t\"php\"  => '\''/opt/bin/php8-cli'\'',"
            print "\t\t\"curl\" => '\''/opt/bin/curl'\'',"
            print "\t\t\"gzip\" => '\''/opt/bin/gzip'\'',"
            print "\t\t\"id\"   => '\''/opt/bin/id'\'',"
            print "\t\t\"stat\" => '\''/opt/bin/stat'\'',"
            print "\t);"
            inserted=1
            next
        }
        /^[[:space:]]*\$topDirectory[[:space:]]*=/ { next }
        /^[[:space:]]*\$pathToExternals[[:space:]]*=/ {
            skip=1
            next
        }
        skip {
            if ($0 ~ /^[[:space:]]*\);/) {
                skip=0
            }
            next
        }
        { print }
        END {
            if (!inserted) {
                print "$topDirectory = '\''" top "'\'';"
            }
        }
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
}

ensure_rutorrent_plugins_installed() {
    rut_web="$1"
    plugins_dir="${rut_web}/plugins"
    mkdir -p "$plugins_dir"

    if [ -d "${plugins_dir}/_getdir" ] && [ -d "${plugins_dir}/rss" ]; then
        return 0
    fi

    tmp="/share/Public/rutorrent-master.tar.gz"
    src="/share/Public/ruTorrent-master"
    url="https://github.com/Novik/ruTorrent/archive/refs/heads/master.tar.gz"

    log "Installing missing ruTorrent plugins from upstream..."
    rm -f "$tmp"
    rm -rf "$src"
    wget -O "$tmp" "$url" || curl -L -o "$tmp" "$url"
    tar -xzf "$tmp" -C /share/Public

    if [ -d "${src}/plugins" ]; then
        cp -a "${src}/plugins/." "$plugins_dir/"
        chmod -R 777 "$plugins_dir" 2>/dev/null || true
    else
        log "WARN: upstream plugin archive did not contain plugins/"
    fi

    rm -f "$tmp"
    rm -rf "$src"
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
  fi
  if ! grep -q 'X-Frame-Options' "$lighttpd_conf" 2>/dev/null; then
      printf '\nsetenv.add-response-header = (\n  "X-Frame-Options" => "SAMEORIGIN"\n)\n' >> "$lighttpd_conf"
  fi

  start_lighttpd_stack "$lighttpd_conf" "$lighttpd_bin" "$php_cgi" || \
      log "WARN: lighttpd restart failed - run: sh scripts/19-finish-multiuser-webui.sh"
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
