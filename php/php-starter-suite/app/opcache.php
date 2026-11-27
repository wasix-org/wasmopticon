<?php

header('Content-Type: application/json');
$status = function_exists('opcache_get_status') ? opcache_get_status(false) : false;
echo json_encode([
    'index_mtime' => filemtime(__DIR__.'/index.php'),
    'index_cached' => function_exists('opcache_is_script_cached')
        && opcache_is_script_cached(__DIR__.'/index.php'),
    'validate_timestamps' => ini_get('opcache.validate_timestamps'),
    'revalidate_freq' => ini_get('opcache.revalidate_freq'),
    'statistics' => $status['opcache_statistics'] ?? null,
], JSON_THROW_ON_ERROR);
