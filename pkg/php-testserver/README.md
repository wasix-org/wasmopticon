# php testserver

PHP webserver using the PHP builtin development server.

Supported routes:

* `/phpinfo`:
  Just dump the regular `phpinfo()` data.

* `/file-get-contents/<URI>`
  Retrieve a file through `file_get_contents()`, and return the file in the
  response.
  For example, to fetch a URL, send a request for: `/file-get-contents/https://www.example.com` 

* `/dns-resolve/<DOMAIN>`:
  Resolve a domain name to an IP address.
  Returns an array with the resolved IP addresses.
  NOTE: php only supports resolving a single address, so the array will only
  have one entry.

  Eg: `/dns-resolve/www.example.com`

