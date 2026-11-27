<?php

$path = '/tmp/suite-upload.bin';
if (! is_file($path)) {
    http_response_code(404);
    exit;
}
header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename="suite-upload.bin"');
header('Content-Length: '.filesize($path));
readfile($path);
