<?php

header('Content-Type: application/json');
$client = $_GET['client'] ?? '';
$case = $_GET['case'] ?? '';
if (! in_array($client, ['curl', 'stream'], true) || ! in_array($case, ['ok', 'timeout'], true)) {
    http_response_code(400);
    exit;
}

$host = getenv('UPSTREAM_HOST');
$port = (int) getenv($case === 'ok' ? 'UPSTREAM_PORT' : 'TIMEOUT_PORT');
if ($client === 'curl') {
    $handle = curl_init("http://$host:$port/probe");
    curl_setopt_array($handle, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT_MS => 500,
        CURLOPT_TIMEOUT_MS => 4000,
        CURLOPT_PROXY => '',
    ]);
    $start = hrtime(true);
    $body = curl_exec($handle);
    $result = [
        'ok' => $body !== false,
        'error' => curl_errno($handle),
        'message' => curl_error($handle),
        'status' => curl_getinfo($handle, CURLINFO_RESPONSE_CODE),
        'body' => $body,
    ];
} else {
    $start = hrtime(true);
    $socket = @stream_socket_client("tcp://$host:$port", $error, $message, 0.5);
    $result = ['ok' => $socket !== false, 'error' => $error, 'message' => $message];
    if ($socket !== false) {
        stream_set_timeout($socket, 4);
        fwrite($socket, "GET /probe HTTP/1.0\r\nHost: localhost\r\n\r\n");
        $response = stream_get_contents($socket);
        [$headers, $body] = explode("\r\n\r\n", $response, 2);
        $result['status_line'] = strtok($headers, "\r\n");
        $result['body'] = $body;
        fclose($socket);
    }
}
$result['elapsed_ms'] = (hrtime(true) - $start) / 1000000;
echo json_encode($result, JSON_THROW_ON_ERROR);
