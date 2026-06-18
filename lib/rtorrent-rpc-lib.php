<?php
// Shared rtorrent XMLRPC-over-SCGI helpers.

function xml_value($value) {
    return '<value><string>' . htmlspecialchars($value, ENT_XML1 | ENT_COMPAT, 'UTF-8') . '</string></value>';
}

function rpc_call($socket, $method, $params) {
    $paramsXml = '';
    foreach ($params as $param) {
        $paramsXml .= '<param>' . xml_value($param) . '</param>';
    }

    $body = '<?xml version="1.0"?>'
        . '<methodCall><methodName>' . htmlspecialchars($method, ENT_XML1 | ENT_COMPAT, 'UTF-8') . '</methodName>'
        . '<params>' . $paramsXml . '</params></methodCall>';

    $headers = "CONTENT_LENGTH\0" . strlen($body)
        . "\0SCGI\0" . "1\0REQUEST_METHOD\0POST\0REQUEST_URI\0/RPC2\0";
    $request = strlen($headers) . ':' . $headers . ',' . $body;

    $stream = @stream_socket_client('unix://' . $socket, $errno, $errstr, 10);
    if (!$stream) {
        throw new RuntimeException("SCGI connect failed: $errno $errstr");
    }

    stream_set_timeout($stream, 20);
    fwrite($stream, $request);

    $response = '';
    $expectedBodyLength = null;
    $bodyStart = null;
    while (!feof($stream)) {
        $chunk = fread($stream, 8192);
        if ($chunk !== false) {
            $response .= $chunk;
        }

        if ($bodyStart === null) {
            $headerEnd = strpos($response, "\r\n\r\n");
            $separatorLength = 4;
            if ($headerEnd === false) {
                $headerEnd = strpos($response, "\n\n");
                $separatorLength = 2;
            }

            if ($headerEnd !== false) {
                $headersText = substr($response, 0, $headerEnd);
                $bodyStart = $headerEnd + $separatorLength;
                if (preg_match('/Content-Length:\s*(\d+)/i', $headersText, $matches)) {
                    $expectedBodyLength = (int)$matches[1];
                }
            }
        }

        if ($expectedBodyLength !== null && $bodyStart !== null) {
            if (strlen($response) >= $bodyStart + $expectedBodyLength) {
                break;
            }
        } elseif (strpos($response, '</methodResponse>') !== false) {
            break;
        }

        $meta = stream_get_meta_data($stream);
        if (!empty($meta['timed_out'])) {
            throw new RuntimeException('SCGI read timed out');
        }
    }

    $xmlStart = strpos($response, '<?xml');
    if ($xmlStart === false) {
        throw new RuntimeException('No XML response: ' . substr($response, 0, 200));
    }

    $xml = simplexml_load_string(substr($response, $xmlStart));
    if (!$xml) {
        throw new RuntimeException('Invalid XML response');
    }

    if (isset($xml->fault)) {
        $fault = parse_rpc_value($xml->fault->value);
        throw new RuntimeException('XMLRPC fault: ' . json_encode($fault));
    }

    return parse_rpc_value($xml->params->param->value);
}

function parse_rpc_value($value) {
    if (isset($value->array)) {
        $result = [];
        foreach ($value->array->data->value as $item) {
            $result[] = parse_rpc_value($item);
        }
        return $result;
    }

    if (isset($value->struct)) {
        $result = [];
        foreach ($value->struct->member as $member) {
            $result[(string)$member->name] = parse_rpc_value($member->value);
        }
        return $result;
    }

    foreach (['string', 'int', 'i4', 'i8', 'boolean', 'double'] as $type) {
        if (isset($value->{$type})) {
            return (string)$value->{$type};
        }
    }

    return trim((string)$value);
}

function rpc_download_hashes($socket) {
    $list = rpc_call($socket, 'download_list', []);
    if (!is_array($list)) {
        return [];
    }
    return array_map('strtolower', $list);
}

function rpc_torrent_loaded($socket, $hash) {
    $hash = strtolower($hash);
    return in_array($hash, rpc_download_hashes($socket), true);
}
