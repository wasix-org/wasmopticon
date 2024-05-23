<?php

error_reporting(E_ALL);
ini_set('display_errors', 1);

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
    exit;

	// Send an http request to the specified URL and return the body, using
	// the get_file_contents() function.
	case 'file-get-contents':
	  handler_file_get_contents($args);
	  break;

	default:
	  print('PHP testserver\n');
	  print('Use one of the available routes for specific tests.\n');
	}
}

router();

?>
