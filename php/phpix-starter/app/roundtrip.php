<?php
header('Content-Type: text/plain; charset=UTF-8');
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    http_response_code(405);
    exit;
}

$body = file_get_contents('php://input');
if ($body === false) {
    http_response_code(500);
    exit;
}
$file = tmpfile();
if ($file === false
    || fwrite($file, $body) !== strlen($body)
    || !rewind($file)
    || stream_get_contents($file) !== $body) {
    http_response_code(500);
    exit;
}
fclose($file);
echo 'roundtrip:', $body;
