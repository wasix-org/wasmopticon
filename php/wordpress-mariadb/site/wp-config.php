<?php

define('DB_NAME', getenv('DB_NAME'));
define('DB_USER', getenv('DB_USERNAME'));
define('DB_PASSWORD', getenv('DB_PASSWORD'));
define('DB_HOST', getenv('DB_HOST') . ':' . getenv('DB_PORT'));
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');
define('WP_HOME', getenv('WP_SITEURL'));
define('WP_SITEURL', getenv('WP_SITEURL'));
define('DISABLE_WP_CRON', true);
define('WP_AUTO_UPDATE_CORE', false);
define('WP_HTTP_BLOCK_EXTERNAL', true);
define('WP_DEBUG', false);

$table_prefix = 'wp_';
require_once __DIR__ . '/wp-settings.php';
