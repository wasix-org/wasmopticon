<?php

error_reporting(E_ALL);
ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');

require_once 'bench_url.php';
require_once 'bench_php.php';

function handler_file_get_contents($args) {
  if ($args === '') {
    throw new Exception('Must provide a valid URI for file_get_contents');
  }

  // Hack because $_SERVER['SCRIPT_NAME'] strips extra slashes...
  $args = str_replace('https:/', 'https://', $args);
  $args = str_replace('http:/', 'http://', $args);

  $url = parse_url($args);
  if ($url === false) {
    http_response_code(400);
    print('can not proxy invalid url: "$args"');
  }

  $body = file_get_contents($args);
  print($body);
}

function handler_echo() {
  // TODO: different formats...
  
  $data = [
    "uri" => $_SERVER["REQUEST_URI"],
    "method" => $_SERVER["REQUEST_METHOD"],
    "headers" => getallheaders(),
  ];
  $body = json_encode($data, JSON_PRETTY_PRINT);
  echo $body;
}

function handler_generate() {
  /// Get the "body-size" query param.
  $body_size = $_GET['body-size'] ?? 0;

  // repeat the string to the desired size.
  $body = str_repeat('0', $body_size);
  print($body);
}

function handler_fs($args) {
  $parts = explode('/', $args, 2);
  $action = $parts[0];

  $path = null;
  if (count($parts) > 1) {
    $path = $parts[1];
  }
  if ($path !== null && $path[0] !== '/') {
    $path = "/$path";
  }

  switch ($parts[0]) {
    case 'read':
      if ($path === null) {
        throw new Exception('URL must end with a path to read');
      }
      if (!file_exists($path)) {
        throw new Exception("File does not exist: '$path'");
      }

      $content = file_get_contents($path);
      print($content);
      break;

    case 'write':
      if ($path === null) {
        throw new Exception('URL must end with a path to write');
      }

      // Ensure parent dir exists
      $dir = dirname($path);
      if (!is_dir($dir)) {
        mkdir($dir, 0777, true);
      }

      $content = file_get_contents('php://input');
      $len = strlen($content);
      file_put_contents($path, $content);
      echo "file contents writen to '$path' ($len bytes)";
      break;

    case 'list':
      if ($path === null) {
        throw new Exception('URL must end with a path to list');
      }
      // check if path is a directory
      if (!is_dir($path)) {
        throw new Exception("Path is not a directory: '$path'");
      }

      $files = scandir($path);

      $accept = $_SERVER['HTTP_ACCEPT'] ?? null;
      if ($accept === 'application/json') {
        print(json_encode($files, JSON_PRETTY_PRINT));
      } else {
        $out = '';
        foreach ($files as $file) {
          if ($file === '.' || $file === '..') {
            continue;
          }
          $out .= "$file\n";
        }
        print($out);
      }
      break;

    default:
      throw new Exception("Invalid fs command '$action'");
  }
}

function handler_benchmark_url_fetch() {
  $url = $_GET['url'] ?? null;
  $count = $_GET['count'] ?? 1;

  if ($url === null) {
    throw new Exception('Missing required parameter: url');
  }

  $results = benchmark_website($url, $count);
  print(json_encode($results, JSON_PRETTY_PRINT));
}

function handler_benchmark_php() {
  $results = PHPBench::bench();
  print(json_encode($results, JSON_PRETTY_PRINT));
}

function router() {
  $path = ltrim($_SERVER['SCRIPT_NAME'], '/');

  $route = '';
  $args = '';

  if (str_contains($path, '/')) {
    $parts = explode('/', $path, 2);
    $route = $parts[0];
    $args = $parts[1];
  } else {
    $route = $path;
  }

  switch ($route) {
  // Show phpinfo
  case 'phpinfo':
    phpinfo();
    break;

  case 'echo':
    handler_echo();
    break;

  case 'generate':
    handler_generate();
    break;

  case 'fs':
    handler_fs($args);
    break;


  case 'benchmark-php':
    handler_benchmark_php();
    break;

  case 'benchmark-url-fetch':
    handler_benchmark_url_fetch();
    break;

  case 'dns-resolve':
    $ip = gethostbyname($args);
    print(json_encode([$ip], JSON_PRETTY_PRINT));
    break;

  // Send an http request to the specified URL and return the body, using
  // the get_file_contents() function.
  case 'file-get-contents':
    handler_file_get_contents($args);
    break;

  default:
    print('<html><body>PHP testserver<br/><br/>');
    print('Use one of the available routes for specific tests.');
    print('</body></html>');
    break;
  }
}

router();

?>
