<?php
// Print the "info.name" field from a .torrent file.
// Usage: php lib/torrent-name.php /path/file.torrent

if ($argc < 2) {
    fwrite(STDERR, "Usage: php torrent-name.php <file.torrent>\n");
    exit(2);
}

$data = @file_get_contents($argv[1]);
if ($data === false) {
    fwrite(STDERR, "Cannot read torrent file\n");
    exit(1);
}

$offset = 0;

function bdecode_value($data, &$offset) {
    $char = $data[$offset] ?? '';

    if ($char === 'i') {
        $offset++;
        $end = strpos($data, 'e', $offset);
        $number = substr($data, $offset, $end - $offset);
        $offset = $end + 1;
        return (int)$number;
    }

    if ($char === 'l') {
        $offset++;
        $list = [];
        while (($data[$offset] ?? '') !== 'e') {
            $list[] = bdecode_value($data, $offset);
        }
        $offset++;
        return $list;
    }

    if ($char === 'd') {
        $offset++;
        $dict = [];
        while (($data[$offset] ?? '') !== 'e') {
            $key = bdecode_value($data, $offset);
            $dict[$key] = bdecode_value($data, $offset);
        }
        $offset++;
        return $dict;
    }

    if (ctype_digit($char)) {
        $colon = strpos($data, ':', $offset);
        $length = (int)substr($data, $offset, $colon - $offset);
        $offset = $colon + 1;
        $string = substr($data, $offset, $length);
        $offset += $length;
        return $string;
    }

    throw new RuntimeException("Invalid bencode at offset $offset");
}

try {
    $torrent = bdecode_value($data, $offset);
    $name = $torrent['info']['name.utf-8'] ?? $torrent['info']['name'] ?? '';
    if ($name === '') {
        exit(1);
    }
    echo $name . "\n";
} catch (Throwable $e) {
    fwrite(STDERR, $e->getMessage() . "\n");
    exit(1);
}
