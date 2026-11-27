# Symfony Messenger

Authored by Codex. This fixture extends the pinned Symfony LTS starter
with a Doctrine Messenger transport on SQLite. The Composer manifest
and lock pin the additional Messenger and Doctrine dependencies.

The HTTP endpoint queues three messages. A separate `wasmer run` mounts
the same temporary database and runs Symfony's `bin/console
messenger:consume fixture --limit=3`. The results route checks the
queue was emptied and exactly the three expected payloads were handled.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 ./test.sh
WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 ./test.sh
```

The default HTTP port is 18261. The test launcher supplies
`SCRIPT_FILENAME` when loading `bin/console` through PHPix CLI so the
Symfony Runtime bootstrap executes the command.
