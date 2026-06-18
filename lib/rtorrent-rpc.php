<?php
// Minimal rtorrent XMLRPC-over-SCGI helper.
// Usage: php lib/rtorrent-rpc.php <method> [string-param...]

require_once __DIR__ . '/rtorrent-rpc-lib.php';

$socket = getenv('RTORRENT_SCGI_SOCKET') ?: '/share/Rdownload/entware/rtorrent.sock';
if (!function_exists('simplexml_load_string')) {
    fwrite(STDERR, "PHP XML extension required. On Entware run: /opt/bin/opkg install php8-mod-simplexml\n");
    exit(2);
}
if ($argc < 2) {
    fwrite(STDERR, "Usage: php rtorrent-rpc.php <method> [params...]\n");
    exit(2);
}

$method = $argv[1];
$params = array_slice($argv, 2);

try {
    $result = rpc_call($socket, $method, $params);
    if (is_array($result)) {
        echo json_encode($result, JSON_UNESCAPED_SLASHES) . "\n";
    } else {
        echo $result . "\n";
    }
} catch (Throwable $e) {
    fwrite(STDERR, $e->getMessage() . "\n");
    exit(1);
}
