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

// rTorrent 0.15 XMLRPC: almost all commands need a target as arg0.
// load.* commands use "" (empty hash) then the file path or raw data.
$attempts = [
    ['load.normal', ['', $path]],
    ['load.start', ['', $path]],
    ['load.raw', ['', base64_encode($raw)]],
    ['load.raw', ['', $raw]],
    ['load.raw_start', ['', base64_encode($raw)]],
];

$errors = [];
$before = rpc_download_hashes($socket);

foreach ($attempts as [$method, $params]) {
    try {
        $result = rpc_call($socket, $method, $params);
        $hash = strtolower(trim((string)$result));

        if ($hash !== '' && preg_match('/^[0-9a-f]{40}$/', $hash)) {
            echo "$hash\n";
            exit(0);
        }

        $after = rpc_download_hashes($socket);
        $new = array_values(array_diff($after, $before));
        if (count($new) === 1) {
            echo $new[0] . "\n";
            exit(0);
        }
        if (count($after) > count($before)) {
            echo "OK\n";
            exit(0);
        }
    } catch (Throwable $e) {
        $errors[] = "$method: " . $e->getMessage();
    }
}

fwrite(STDERR, implode("\n", $errors) . "\n");
exit(1);
