<?php

header('Content-Type: application/json');
if (! session_start()) {
    http_response_code(500);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $value = $_POST['value'] ?? '';
    if (! is_string($value) || ! preg_match('/^session-[0-9]+$/D', $value)) {
        http_response_code(400);
        exit;
    }
    $_SESSION['value'] = $value;
    $_SESSION['writes'] = ($_SESSION['writes'] ?? 0) + 1;
    usleep(100000);
}

$result = [
    'id' => session_id(),
    'value' => $_SESSION['value'] ?? null,
    'writes' => $_SESSION['writes'] ?? 0,
];
session_write_close();
echo json_encode($result, JSON_THROW_ON_ERROR);
