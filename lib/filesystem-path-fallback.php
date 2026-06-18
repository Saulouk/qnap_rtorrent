<?php
// Filesystem fallback: match torrent names to folders under a data root.
// Appends rows for hashes missing from the path map.
// Usage: php filesystem-path-fallback.php <torrent_dir> <data_root> <path_map.tsv>

require_once __DIR__ . '/torrent-name.php';

$torrentDir = $argv[1] ?? '/share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720';
$dataRoot = $argv[2] ?? '/share/SN';
$mapFile = $argv[3] ?? '/share/Public/rtorrent-debug-backup/historic-path-map.tsv';

function hash_from_file($path) {
    if (preg_match('/^([0-9A-Fa-f]{40})\.torrent$/', basename($path), $m)) {
        return strtoupper($m[1]);
    }
    return null;
}

function torrent_display_name($torrentFile) {
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__DIR__ . '/torrent-name.php') . ' ' . escapeshellarg($torrentFile);
    return trim(shell_exec($cmd) ?? '');
}

function find_unique_parent($dataRoot, $name) {
    $matches = [];
    $iter = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($dataRoot, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::SELF_FIRST
    );
    $depth = 0;
    foreach ($iter as $item) {
        $depth = $iter->getDepth();
        if ($depth > 8) {
            continue;
        }
        if ($item->getFilename() === $name) {
            $matches[] = dirname($item->getPathname());
        }
    }
    $matches = array_values(array_unique($matches));
    if (count($matches) === 1) {
        return ['path' => $matches[0], 'status' => 'filesystem'];
    }
    if (count($matches) > 1) {
        return ['path' => implode(';', $matches), 'status' => 'ambiguous'];
    }
    return null;
}

$existing = [];
if (is_file($mapFile)) {
    $fp = fopen($mapFile, 'r');
    $first = true;
    while (($line = fgets($fp)) !== false) {
        if ($first) {
            $first = false;
            continue;
        }
        $cols = explode("\t", rtrim($line, "\r\n"));
        if (!empty($cols[0]) && !empty($cols[2])) {
            $existing[strtoupper($cols[0])] = true;
        }
    }
    fclose($fp);
}

$added = 0;
$fp = is_file($mapFile) ? fopen($mapFile, 'a') : fopen($mapFile, 'w');
if (!is_file($mapFile) || filesize($mapFile) === 0) {
    fwrite($fp, "hash\tname\told_path\tsource\tvia\n");
}

foreach (glob(rtrim($torrentDir, '/') . '/*.torrent') as $torrent) {
    $hash = hash_from_file($torrent);
    if ($hash === null || isset($existing[$hash])) {
        continue;
    }
    $name = torrent_display_name($torrent);
    if ($name === '') {
        continue;
    }
    $match = find_unique_parent($dataRoot, $name);
    if ($match === null) {
        continue;
    }
    $via = $match['status'] === 'ambiguous' ? 'filesystem-ambiguous' : 'filesystem-match';
    fwrite($fp, implode("\t", [
        $hash,
        str_replace(["\t", "\n", "\r"], ' ', $name),
        str_replace(["\t", "\n", "\r"], ' ', $match['path']),
        $torrent,
        $via,
    ]) . "\n");
    $added++;
}

fclose($fp);
echo "Filesystem fallback added $added rows to $mapFile\n";
