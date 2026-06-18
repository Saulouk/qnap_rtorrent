<?php
// Scan old rtorrent backups and build hash => historic path map.
// Usage: php extract-historic-paths.php <source_dir> [output.tsv]

require_once __DIR__ . '/bencode.php';

$sourceDir = $argv[1] ?? '/share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720';
$outFile = $argv[2] ?? '/share/Public/rtorrent-debug-backup/historic-path-map.tsv';

$pathKeys = [
    'directory', 'directory_base', 'base_path', 'path', 'download_path',
    'custom1', 'custom2', 'custom3', 'custom4', 'custom5',
    'tied_to_file', 'session_file',
];

function is_path_like($s) {
    if (!is_string($s) || strlen($s) < 2) {
        return false;
    }
    if (preg_match('#^/(share|mnt|home|volume)#i', $s)) {
        return true;
    }
    if (preg_match('#^(Movies|Drama Series|Software|TV|Downloads)(/|$)#', $s)) {
        return true;
    }
    return false;
}

function collect_paths($node, $key = null, &$found = []) {
    if (is_string($node)) {
        if ($key !== null && in_array($key, $GLOBALS['pathKeys'], true)) {
            if (is_path_like($node)) {
                $found[] = ['path' => $node, 'via' => "key:$key"];
            }
        } elseif (is_path_like($node)) {
            $found[] = ['path' => $node, 'via' => 'string'];
        }
        return;
    }
    if (is_array($node)) {
        $isDict = false;
        foreach (array_keys($node) as $k) {
            if (!is_int($k)) {
                $isDict = true;
                break;
            }
        }
        if ($isDict) {
            foreach ($node as $k => $v) {
                collect_paths($v, is_string($k) ? $k : null, $found);
            }
        } else {
            foreach ($node as $v) {
                collect_paths($v, null, $found);
            }
        }
    }
}

function hash_from_basename($base) {
    if (preg_match('/^([0-9A-Fa-f]{40})(?:\.torrent(?:\.(?:rtorrent|libtorrent_resume))?)?$/', $base, $m)) {
        return strtoupper($m[1]);
    }
    return null;
}

function torrent_name_from_file($torrentFile) {
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__DIR__ . '/torrent-name.php') . ' ' . escapeshellarg($torrentFile);
    $name = trim(shell_exec($cmd) ?? '');
    return $name !== '' ? $name : null;
}

function pick_best_path($candidates) {
    if (empty($candidates)) {
        return null;
    }
    usort($candidates, function ($a, $b) {
        $score = function ($c) {
            $p = $c['path'];
            $s = strlen($p);
            if (strpos($p, '/share/') === 0) {
                $s += 1000;
            }
            if (strpos($c['via'], 'key:') === 0) {
                $s += 500;
            }
            if (preg_match('#/(Movies|Drama Series|Software|TV)(/|$)#', $p)) {
                $s += 200;
            }
            return $s;
        };
        return $score($b) <=> $score($a);
    });
    return $candidates[0];
}

function scan_file($file, &$byHash) {
    $base = basename($file);
    $hash = hash_from_basename($base);
    if ($hash === null && preg_match('/^([0-9A-Fa-f]{40})$/', $base, $m)) {
        $hash = strtoupper($m[1]);
    }
    if ($hash === null) {
        return;
    }

    $found = [];
    $decoded = bdecode_file($file);
    if ($decoded !== null) {
        collect_paths($decoded, null, $found);
    }

    // strings fallback for partially corrupt files
    $raw = @file_get_contents($file);
    if ($raw !== false) {
        if (preg_match_all('#(/share(?:/CACHEDEV[0-9]+_DATA)?/[^\x00-\x1f\x7f"]+)#', $raw, $m)) {
            foreach ($m[1] as $p) {
                $p = rtrim($p, " \t\r\n\0");
                if (is_path_like($p)) {
                    $found[] = ['path' => $p, 'via' => 'strings'];
                }
            }
        }
        if (preg_match_all('#((?:Movies|Drama Series|Software|TV|Downloads)/[^\x00-\x1f\x7f"]*)#', $raw, $m2)) {
            foreach ($m2[1] as $p) {
                $found[] = ['path' => '/' . rtrim($p, " \t\r\n\0"), 'via' => 'strings-category'];
            }
        }
    }

    $best = pick_best_path($found);
    if ($best === null) {
        return;
    }

    $viaScore = function ($via) {
        $scores = [
            'key:directory' => 100,
            'key:directory_base' => 95,
            'key:base_path' => 90,
            'key:path' => 85,
            'string' => 50,
            'strings' => 40,
            'strings-category' => 30,
            'filesystem-match' => 20,
        ];
        return $scores[$via] ?? 10;
    };

    $newScore = $viaScore($best['via']) + min(strlen($best['path']), 200);
    $oldScore = isset($byHash[$hash])
        ? $viaScore($byHash[$hash]['via']) + min(strlen($byHash[$hash]['path']), 200)
        : -1;

    if ($newScore > $oldScore) {
        $byHash[$hash] = [
            'hash' => $hash,
            'path' => $best['path'],
            'via' => $best['via'],
            'source' => $file,
        ];
    }
}

$byHash = [];
$iterator = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($sourceDir, FilesystemIterator::SKIP_DOTS)
);

foreach ($iterator as $fileInfo) {
    if (!$fileInfo->isFile()) {
        continue;
    }
    $path = $fileInfo->getPathname();
    $base = $fileInfo->getFilename();
    if (preg_match('/\.(torrent|rtorrent|libtorrent_resume)$/', $base) || preg_match('/^[0-9A-Fa-f]{40}$/', $base)) {
        scan_file($path, $byHash);
    }
}

// Attach torrent names from companion .torrent files
foreach ($byHash as $hash => &$row) {
    $torrent = null;
    $candidates = [
        dirname($row['source']) . "/$hash.torrent",
        $sourceDir . "/$hash.torrent",
    ];
    foreach ($candidates as $c) {
        if (is_file($c)) {
            $torrent = $c;
            break;
        }
    }
    $row['name'] = $torrent ? torrent_name_from_file($torrent) : '';
    $row['torrent_file'] = $torrent ?: '';
}
unset($row);

@mkdir(dirname($outFile), 0777, true);
$fp = fopen($outFile, 'w');
fwrite($fp, "hash\tname\told_path\tsource\tvia\n");
foreach ($byHash as $row) {
    fwrite($fp, implode("\t", [
        $row['hash'],
        str_replace(["\t", "\n", "\r"], ' ', $row['name'] ?? ''),
        str_replace(["\t", "\n", "\r"], ' ', $row['path']),
        $row['source'],
        $row['via'],
    ]) . "\n");
}
fclose($fp);

echo "Wrote " . count($byHash) . " path entries to $outFile\n";
