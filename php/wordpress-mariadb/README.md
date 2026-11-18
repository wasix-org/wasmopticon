# WordPress and MariaDB

This fixture packages a pinned WordPress release with Anybuild 0.33.3 and
the 32-bit PHPix 8.4 runtime. It uses the WordPress provider's
`after_deploy` job and PHPix startup script. The application uses a
minimal theme, a seeded post and a disposable MariaDB container.

Build and test using Docker, Bash, curl, jq, GNU coreutils, and the
corresponding Wasmer binaries.

```sh
ANYBUILD_BIN=/path/to/anybuild WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18150 ./test.sh
WASMER_BIN=/path/to/wasmer-next WASIX_LANE=v2 PORT=18150 ./test.sh
```

Keep this directory beside `phpix-starter`, whose runtime downloader and
lockfile are used by `build.sh`. The WordPress archive checksum, WP-CLI
checksum and MariaDB image digest live in `inputs.env`. Anybuild stages the
pinned WP-CLI release and the build verifies its checksum before packaging.
The build leaves the WebC at `.anybuild/suite/package.webc` and a link to
the matching generated manifests at `.anybuild/suite/manifest`.

Each test creates a fresh MariaDB data directory in the container's tmpfs
and a writable `wp-content` in its run directory. It verifies the DB
connection before running `after_deploy`, seeds the test post and checks
home, the permalink, the REST response and the upload. It restarts PHPix
while retaining MariaDB and `wp-content`, then runs the same checks.
Everything is served on host loopback. The harness removes the container
and preserves logs and test responses under `.anybuild/suite/runs/`.

For an opt-in load run, pass a command to `test.sh`. The harness runs it
after the restart checks with the active loopback `TARGET_URL` and the
Docker container name in `MARIADB_CONTAINER`, then checks the site again.
Set `WORDPRESS_WEBC` to test a retained package or `MARIADB_CPUSET` to
pin the DB container's CPUs. Use Artillery 2.0.34 with `artillery.yml` and pass
`--target "$TARGET_URL"` from the load command.
