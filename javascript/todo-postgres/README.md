# Astro + Drizzle PostgreSQL todo app

A deliberately small todo app demonstrating Astro SSR, Drizzle ORM, and a
Wasmer-managed PostgreSQL database. Every interaction is an ordinary HTML form
submission, so the browser receives no client-side JavaScript. Pressing Enter in
the new-todo field submits the form.

- Dev app: <https://todo-js-postgres.wasmer.app>
- Admin dashboard: <https://wasmer.io/apps/wasmer-tests/todo-js-postgres>
- Tracking issue: <https://linear.app/wasmer/issue/ECO-427/wasmopticon-add-postgres-astro-javascript-todo-app>

## How it works

`src/pages/index.astro` reads and renders todos on the server. Form posts go to
`src/pages/todos.ts`, which validates the request and performs create, toggle,
or delete operations before redirecting back to the list. Todos include a
database-generated creation timestamp, shown in UTC in the UI.

`src/db/schema.ts` defines the PostgreSQL table with Drizzle. Both the app and
`scripts/migrate.mjs` use Drizzle's `node-postgres` adapter. The `pg` package is
the pure-JavaScript node-postgres driver; the optional `pg-native` package is not
installed.

## Local development

Requirements: Node.js 24+, npm, and PostgreSQL. For example, start a disposable
local database with Docker:

```sh
docker run --name todo-postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=todos \
  -p 5432:5432 \
  -d postgres:17
```

Then install, migrate, and start the app:

```sh
cp .env.example .env
npm ci
npm run migrate
npm run dev
```

Astro serves the app at <http://localhost:4321>. The `.env.example` values match
the Docker command above.

The connection uses the variables that Wasmer injects for managed databases:

| Variable | Meaning |
| --- | --- |
| `DB_HOST` | PostgreSQL host |
| `DB_PORT` | PostgreSQL port |
| `DB_NAME` | Database name |
| `DB_USERNAME` | Database user |
| `DB_PASSWORD` | Database password |

The Wasmer database endpoint uses TLS by default. `DB_SSL=false` is an optional
local-development override included in `.env.example` because the Docker image
above does not enable TLS. Certificate verification is disabled for Wasmer's
managed endpoint, matching its connection requirements; do not reuse this pool
configuration for an untrusted database host.

## Commands

| Command | Purpose |
| --- | --- |
| `npm run dev` | Run Astro's development server |
| `npm run check` | Type-check the Astro project |
| `npm run migrate` | Apply pending checked-in Drizzle SQL migrations |
| `npm run build` | Build the standalone Astro server and package the migration entrypoint |
| `npm start` | Run the production server from `dist/` |

To test the production build locally:

```sh
npm run build
HOST=0.0.0.0 PORT=8080 npm start
```

Migrations live in `drizzle/` and are tracked by
`drizzle/meta/_journal.json`. Add schema changes as a new numbered SQL migration
rather than modifying a migration that may already have run, then use
`npm run migrate` locally before deploying.

## Deploy to Wasmer

`app.yaml` requests PostgreSQL through `capabilities.database` and contains no
database credentials. Wasmer provisions the database and supplies the five
`DB_*` variables above. The `migrate-database` job runs after deployment and
invokes the named `migrate` command exported from `Anybuild`, so migrations use
the package that was just deployed.

Deploy from this directory:

```sh
wasmer deploy --build-remote
```

Astro validates forwarded hosts against the exact public app hostname in
`astro.config.mjs`. This lets its normal same-origin form protection remain
enabled behind Wasmer's reverse proxy.

Useful status commands:

```sh
wasmer app info wasmer-tests/todo-js-postgres
wasmer app logs wasmer-tests/todo-js-postgres
```

## Packaged compatibility test

The packaging and test additions were authored by Codex. The self-contained
`tsconfig.json` mirrors Astro 7.2.0's strict preset so Rolldown can read it from
Anybuild's staging layout.

Build with Node 26.13.1, npm 11.20.0, and Anybuild 0.33.3. Use the local WebC
registry in `registry.sha256`. Pull the pinned PostgreSQL image before testing.
The test starts a disposable loopback-only container with `sudo docker`, runs
the packaged migration, and checks create, toggle, and delete in PostgreSQL
and in the server-rendered page.

The compatibility build embeds a fixed, public test key for reproducibility.
Use the deployment workflow above with a private key or Astro's generated
key when deploying.

```sh
sudo docker pull docker.io/library/postgres@sha256:58b1ad1807d86ca43d0e37fded9f0a899a7ab8763fa9576a63059a52de223e1b
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer-v1 \
  WASIX_LANE=v1 PORT=18300 DB_PORT=18301 ./test.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer-v2 \
  WASIX_LANE=v2 PORT=18300 DB_PORT=18301 ./test.sh
```
