<?php
// Minimal bencode decoder for rtorrent session/sidecar files.

function bdecode_value($data, &$offset) {
    $len = strlen($data);
    if ($offset >= $len) {
        throw new RuntimeException("Unexpected end at offset $offset");
    }

    $char = $data[$offset];

    if ($char === 'i') {
        $offset++;
        $end = strpos($data, 'e', $offset);
        if ($end === false) {
            throw new RuntimeException('Invalid integer');
        }
        $number = substr($data, $offset, $end - $offset);
        $offset = $end + 1;
        return (int)$number;
    }

    if ($char === 'l') {
        $offset++;
        $list = [];
        while ($offset < $len && $data[$offset] !== 'e') {
            $list[] = bdecode_value($data, $offset);
        }
        $offset++;
        return $list;
    }

    if ($char === 'd') {
        $offset++;
        $dict = [];
        while ($offset < $len && $data[$offset] !== 'e') {
            $key = bdecode_value($data, $offset);
            if (!is_string($key)) {
                throw new RuntimeException('Dict key must be string');
            }
            $dict[$key] = bdecode_value($data, $offset);
        }
        $offset++;
        return $dict;
    }

    if (ctype_digit($char)) {
        $colon = strpos($data, ':', $offset);
        if ($colon === false) {
            throw new RuntimeException('Invalid string length');
        }
        $length = (int)substr($data, $offset, $colon - $offset);
        $offset = $colon + 1;
        $string = substr($data, $offset, $length);
        $offset += $length;
        return $string;
    }

    throw new RuntimeException("Invalid bencode at offset $offset (char " . ord($char) . ")");
}

function bdecode_file($path) {
    $data = @file_get_contents($path);
    if ($data === false) {
        return null;
    }
    $offset = 0;
    try {
        return bdecode_value($data, $offset);
    } catch (Throwable $e) {
        return null;
    }
}
