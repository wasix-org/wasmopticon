<?php
$to = $_GET['to'] ?? '';
$subject = $_GET['subject'] ?? '';
$message = $_GET['message'] ?? '';

$ok = mail($to, $subject, $message);

if ($ok) {
  echo "OK";
} else {
  $lastError = error_get_last();
  echo "mail() returned false";
  if ($lastError && isset($lastError["message"])) {
    echo "\n";
    echo $lastError["message"];
  }
}
