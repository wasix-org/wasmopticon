<?php

header('Content-Type: text/plain');
header('Cache-Control: no-store');
while (ob_get_level() > 0) {
    ob_end_flush();
}

echo "start\n";
flush();
sleep(2);
echo "end\n";
flush();
