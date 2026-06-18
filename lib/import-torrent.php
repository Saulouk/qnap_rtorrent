<?php
// Import a .torrent into rtorrent (stopped). Tries rtorrent 0.15 XMLRPC method names.
// Usage: php import-torrent.php <path-to.torrent>
// Prints lowercase info-hash on success.

require_once __DIR__ . '/rtorrent-rpc-lib.php';

if (!function_exists('simplexml_load_string')) {
    fwrite(STDERR, "PHP XML extension required. Run: /opt/bin/opkg install php8-mod-simplexml\n");
    exit(2);
}

$socket = getenv('RTORRENT_SCGI_SOCKET') ?: '/share/Rdownload/entware/rtorrent.sock';
$file = $argv[1] ?? '';

if (!is_file($file)) {
    fwrite(STDERR, "Torrent file not found: $file\n");
    exit(2);
}

$path = $file;
$real = realpath($file);
if ($real !== false) {
    $path = $real;
}

$raw = file_get_contents($file);
if ($raw === false || $raw === '') {
    fwrite(STDERR, "Could not read torrent file: $path\n");
    exit(2);
}

// rtorrent 0.15 exposes command names with dots, not legacy bare "load".
$attempts = [
    ['load.normal', [$path]],
    ['load.start', [$path]],
    ['load.raw', [$raw]],
    ['load.raw_start', [$raw]],
];

$errors = [];
foreach ($attempts as [$method, $params]) {
    try {
        $result = rpc_call($socket, $method, $params);
        $hash = strtolower(trim((string)$result));
        if ($hash !== '' && preg_match('/^[0-9a-f]{40}$/', $hash)) {
            echo "$hash\n";
            exit(0);
        }
        if (rpc_torrent_loaded($socket, $hash !== '' ? $hash : '')) {
            echo "$hash\n";
            exit(0);
        }
        // load.* may return empty string but still add torrent — check session.
        $hashes = rpc_download_hashes($socket);
        if (count($hashes) > 0) {
            // If we can't get hash from response, caller will match by polling.
            echo "OK\n";
            exit(0);
        }
    } catch (Throwable $e) {
        $errors[] = "$method: " . $e->getMessage();
    }
}

fwrite(STDERR, implode("\n", $errors) . "\n");
exit(1);
