<?php

header('Content-Type: application/json');
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Allow: POST');
    exit;
}

$file = $_FILES['payload'] ?? null;
if ($file === null || $file['error'] !== UPLOAD_ERR_OK) {
    $error = $file['error'] ?? UPLOAD_ERR_NO_FILE;
    http_response_code($error === UPLOAD_ERR_INI_SIZE ? 413 : 400);
    echo json_encode(['upload_error' => $error], JSON_THROW_ON_ERROR);
    exit;
}

$path = '/tmp/suite-upload.bin';
if (! move_uploaded_file($file['tmp_name'], $path)) {
    http_response_code(500);
    exit;
}
echo json_encode(['size' => filesize($path), 'sha256' => hash_file('sha256', $path)], JSON_THROW_ON_ERROR);
