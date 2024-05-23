# php testserver

PHP webserver using the PHP builtin development server.

Supported routes:

* `/phpinfo`:
  Just dump the regular `phpinfo()` data.

* `/file-get-contents/<URI>`
  Retrieve a file through `file_get_contents()`, and return the file in the
  response.
  For example, to fetch a URL, send a request for: `/file-get-contents/https://www.example.com` 

