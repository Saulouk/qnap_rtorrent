<?php
// Validate and transform historic path map using path-roots.conf.
// Usage: php validate-historic-paths.php <input.tsv> <output.tsv> [path-roots.conf]

$inFile = $argv[1] ?? '/share/Public/rtorrent-debug-backup/historic-path-map.tsv';
$outFile = $argv[2] ?? '/share/Public/rtorrent-debug-backup/historic-path-map-validated.tsv';
$rootsFile = $argv[3] ?? dirname(__DIR__) . '/path-roots.conf';

function load_roots($file) {
    $roots = [];
    if (!is_file($file)) {
        return $roots;
    }
    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        $parts = explode('=', $line, 2);
        if (count($parts) === 2) {
            $roots[trim($parts[0])] = trim($parts[1]);
        }
    }
    uksort($roots, function ($a, $b) {
        return strlen($b) <=> strlen($a);
    });
    return $roots;
}

function transform_path($oldPath, $roots) {
    $oldPath = rtrim($oldPath, '/');
    if ($oldPath === '') {
        return '';
    }
    foreach ($roots as $oldRoot => $newRoot) {
        $oldRoot = rtrim($oldRoot, '/');
        if ($oldPath === $oldRoot) {
            return $newRoot;
        }
        if (strpos($oldPath, $oldRoot . '/') === 0) {
            return $newRoot . substr($oldPath, strlen($oldRoot));
        }
    }
    if (strpos($oldPath, '/share/SN') === 0) {
        return $oldPath;
    }
    if (preg_match('#^/(Movies|Drama Series|Software|TV|Downloads)(/.*)?$#', $oldPath, $m)) {
        return '/share/SN' . $oldPath;
    }
    return $oldPath;
}

function data_exists($dir, $name) {
    if ($dir === '' || !is_dir($dir)) {
        return false;
    }
    $candidates = [
        $dir,
        $dir . '/' . $name,
    ];
    foreach ($candidates as $path) {
        if ($path !== '' && (is_file($path) || is_dir($path))) {
            return $path;
        }
    }
    return false;
}

$roots = load_roots($rootsFile);
if (!is_file($inFile)) {
    fwrite(STDERR, "Input map not found: $inFile\n");
    exit(1);
}

$rows = [];
$header = null;
$fp = fopen($inFile, 'r');
while (($line = fgets($fp)) !== false) {
    $line = rtrim($line, "\r\n");
    if ($line === '') {
        continue;
    }
    $cols = explode("\t", $line);
    if ($header === null) {
        $header = $cols;
        continue;
    }
    $row = array_pad($cols, 5, '');
    $rows[] = [
        'hash' => $row[0],
        'name' => $row[1],
        'old_path' => $row[2],
        'source' => $row[3] ?? '',
        'via' => $row[4] ?? '',
    ];
}
fclose($fp);

$stats = ['OK' => 0, 'MISSING' => 0, 'AMBIGUOUS' => 0, 'NO_PATH' => 0];

@mkdir(dirname($outFile), 0777, true);
$out = fopen($outFile, 'w');
fwrite($out, "hash\tname\told_path\tnew_path\texists_at\tstatus\tsource\tvia\n");

foreach ($rows as $row) {
    $oldPath = $row['old_path'];
    $name = $row['name'];
    $newPath = transform_path($oldPath, $roots);
    $status = 'MISSING';
    $existsAt = '';

    if ($oldPath === '') {
        $status = 'NO_PATH';
        $stats['NO_PATH']++;
    } else {
        $found = data_exists($newPath, $name);
        if ($found) {
            $status = 'OK';
            $existsAt = $found;
            $stats['OK']++;
        } else {
            $parent = dirname($newPath);
            if ($parent && $parent !== '.' && data_exists($parent, $name)) {
                $status = 'OK';
                $existsAt = data_exists($parent, $name);
                $newPath = $parent;
                $stats['OK']++;
            } else {
                $stats['MISSING']++;
            }
        }
    }

    fwrite($out, implode("\t", [
        $row['hash'],
        str_replace(["\t", "\n", "\r"], ' ', $name),
        str_replace(["\t", "\n", "\r"], ' ', $oldPath),
        str_replace(["\t", "\n", "\r"], ' ', $newPath),
        str_replace(["\t", "\n", "\r"], ' ', $existsAt),
        $status,
        $row['source'],
        $row['via'],
    ]) . "\n");
}
fclose($out);

echo "Validated " . count($rows) . " rows -> $outFile\n";
foreach ($stats as $k => $v) {
    echo "  $k: $v\n";
}
