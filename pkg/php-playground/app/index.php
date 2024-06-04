<?php

$body = '
<html>
  <head>
    <title>PHP Playground</title>
  </head>
  <body>
    <h1>PHP Playground</h1>

    <p>
      <ul>
        <li>
          <a href="/phpinfo.php">phpinfo - Show php environment info</a>
        </li>
        <li>
          <a href="/opcache-gui">PHP OPCache GUI - Show opcache statistics</a>
        </li>
      </ul>
    </p>
  </body>
</html>
';

print($body);

?>
