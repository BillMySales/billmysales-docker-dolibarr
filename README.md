Dolibarr Docker stack
=====================

Docker Compose stack for Dolibarr ERP & CRM, usable for local development and
for simple production deployments (a single server). Maintained by
[BillMySales](https://www.billmysales.com).

| Component  | Image                                        | Default version  |
|------------|----------------------------------------------|------------------|
| Web server | `caddy:<ver>-alpine`                         | 2.11             |
| Dolibarr   | built from `image/` (`php:<ver>-fpm-alpine`) | 24.0.1 / PHP 8.5 |
| Database   | `mariadb`                                    | 12.3 (LTS)       |
| Mailpit    | `axllent/mailpit` (optional, dev)            | v1.31            |

Why an own image: the vendor image (`dolibarr/dolibarr`) only ships Apache
(no PHP-FPM variant), uses PHP 8.2 (end of life in December 2026) and lagged
one release behind. `image/Dockerfile` puts the official release archive on
`php:<ver>-fpm-alpine`, verified with SHA-256 (372 MB). Dolibarr 24 supports
PHP 7.2 to 8.5.

Requirements
------------

- Docker Engine 24+ with the Compose v2 plugin (`docker compose`, 2.24+).
- Development: ports 8106, 8406 and 8025 free on the host.
- Production: a server with ports 80 and 443 reachable, and a DNS record for
  Dolibarr's domain pointing to it.
- The first `up` builds the image (PHP extensions are compiled).

Quick start (development)
-------------------------

```shell
cp .env.dev.example .env
docker compose up -d
docker compose logs -f setup   # wait for "==> Done"
```

- Dolibarr: http://localhost:8106 (user `admin`, password `admin12345`; a
  login, `DOLI_ADMIN_LOGIN`, not an email)
- Mailpit (every email Dolibarr sends): http://localhost:8025

Production
----------

```shell
cp .env.prod.example .env
# Fill in DOLI_URL, SITE_ADDRESS, DB_PASSWORD, DB_ROOT_PASSWORD and
# DOLI_ADMIN_PASSWORD.
# Recommended: the SMTP_* values (without SMTP_HOST no emails are sent).
docker compose up -d
```

- With `SITE_ADDRESS` set to the domain, Caddy gets a Let's Encrypt certificate
  and renews it automatically (certificates live in the `caddy_data` volume).
- Behind an existing Traefik (no host ports), use `overrides/traefik.yaml`
  (see [Overrides](#overrides)).
- Compose refuses to start while a required value is missing.
- Configure SMTP (recommended, not required): without `SMTP_HOST` no emails
  are sent (the image has no local mail server).
- The `backup` profile is enabled by default in the production template.

Services
--------

| Service    | Profile   | Role                                                           |
|------------|-----------|----------------------------------------------------------------|
| `db`       |           | MariaDB, data in the `db_data` volume.                         |
| `dolibarr` |           | PHP-FPM + Dolibarr (port 9000, internal).                      |
| `caddy`    |           | Web server and TLS, the only published ports (80, 443).        |
| `setup`    |           | One-shot job (`scripts/setup.sh`), runs on every `up`.         |
| `cron`     |           | Runs Dolibarr's scheduled jobs every `CRON_INTERVAL` seconds.  |
| `backup`   | `backup`  | DB dump + documents/configuration archive on a schedule.       |
| `mailpit`  | `mailpit` | Development SMTP server that catches all mail.                 |

Volumes:

| Volume      | Mounted at            | Contents                                                        |
|-------------|-----------------------|-----------------------------------------------------------------|
| `code`      | `/var/www/dolibarr`   | `htdocs/` and `scripts/`, synced from the image; keeps          |
|             |                       | `htdocs/conf` (configuration) and `htdocs/custom` (modules).    |
| `documents` | `/var/www/documents`  | Generated and uploaded documents, outside the web root.         |
| `db_data`   | `/var/lib/mysql`      | Database.                                                       |

### What `setup` does

- Syncs the code from the image to the `code` volume when `DOLI_VERSION`
  changes, keeping `htdocs/conf` and `htdocs/custom`.
- Empty database: runs Dolibarr's CLI installer (`install/step1.php`,
  `step2.php`, `step5.php`) and locks the installer (`documents/install.lock`).
- Database older than the code: runs Dolibarr's upgrade scripts
  (`upgrade.php`, `upgrade2.php`, `step5.php`), so **upgrading Dolibarr is
  changing `DOLI_VERSION` and running `docker compose up -d`** (back up first).
  The migration logs "no such table" and "duplicate column" errors for
  modules that aren't enabled: that's normal, Dolibarr tolerates them.
- On every run, writes `htdocs/conf/conf.php` from the environment (URL,
  database, production mode), keeping the values generated at install time
  (instance id...), and, when `SMTP_HOST` is set, the email settings from
  `SMTP_*`.
- Once: default language, company country and name, currency, modules required
  by the country and the Scheduled jobs module (with a random `CRON_KEY`);
  stores `DOCKER_STACK_INITIALIZED`, so later changes made in Dolibarr are kept.

Common commands
---------------

```shell
docker compose ps                              # every service "healthy", setup "Exited (0)"
docker compose logs -f caddy dolibarr cron     # web server, PHP and scheduled jobs logs
docker compose exec dolibarr sh                # shell in the PHP container
docker compose exec db mariadb -u dolibarr -p dolibarr   # SQL shell
docker compose down                            # stop, keep data
docker compose down -v                         # stop and DELETE all data
```

Point of sale
-------------

The TakePOS module is not enabled by default: a shop needs its own setup
(terminals, cash and bank accounts, default customer).

1. Create the accounts payments go to: Bank/Cash > New financial account
   (e.g. a "Cash" account of type cash, and a bank account for cards).
2. Enable the module: Home > Setup > Modules/Applications > TakePOS. Dolibarr
   also enables the modules it needs (Banks & Cash, Invoices, Products,
   Categories).
3. Configure it (the module's setup page, Terminal tab): the default
   customer for anonymous sales and the account for each payment method
   (cash, card, cheque); the warehouse too if the Stocks module is on.
4. Open it from the TakePOS menu. Sales are regular customer invoices, paid
   into the configured accounts.

Backups
-------

With the `backup` profile, the `backup` service writes
`<timestamp>-db.sql.gz` and `<timestamp>-files.tar.gz` (documents,
`htdocs/conf` and `htdocs/custom`; the code comes from the image) to the
`backups` volume (or `./data/backups` with `overrides/local-dirs.yaml`) at
start and then every `BACKUP_INTERVAL_HOURS`, and deletes files older than
`BACKUP_KEEP_DAYS`. Files are readable by their owner only.

```shell
docker compose run --rm --no-deps backup now                  # back up now
docker compose run --rm --no-deps backup list                 # list timestamps
docker compose stop dolibarr cron                   # recommended while restoring
docker compose run --rm --no-deps backup restore <timestamp>  # restore DB and files
docker compose start dolibarr cron
```

`--no-deps` keeps the command from starting `setup` first (with damaged
data `setup` fails and the restore would never run); the database must
be running (`docker compose up -d db` if the stack is down).

Overrides
---------

Optional compose files in `overrides/`, enabled with `COMPOSE_FILE` in `.env`
(several are combined with `:`). Each file documents its variables.

```shell
COMPOSE_FILE=compose.yaml:overrides/traefik.yaml:overrides/local-dirs.yaml
```

| File                         | Purpose                                                           |
|------------------------------|-------------------------------------------------------------------|
| `overrides/traefik.yaml`     | Publish through an existing Traefik on a shared external network: |
|                              | no host ports, Traefik terminates TLS (`TRAEFIK_HOST`, ...).      |
| `overrides/local-dirs.yaml`  | Database, code, documents, Caddy and backups in local directories |
|                              | (`DATA_DIR`, default `./data`) instead of named volumes.          |
| `overrides/module.yaml`      | Mount a module into `htdocs/custom` from a local directory,       |
|                              | editable live (`MODULE_PATH`, `MODULE_NAME`).                     |

A local `compose.override.yaml` (gitignored) is also loaded automatically by
Docker Compose, for changes specific to one machine.

Configuration
-------------

Every variable is documented in `.env.prod.example`. Main groups:

- **Site and network**: `DOLI_URL`, `SITE_ADDRESS`, `HTTP_BIND`, `HTTP_PORT`,
  `HTTPS_PORT`.
- **Credentials**: `DB_PASSWORD`, `DB_ROOT_PASSWORD`, `DOLI_ADMIN_PASSWORD`
  (required), `DOLI_ADMIN_LOGIN`. The admin login and password are
  only used by the installer: changing them later doesn't change the account. `DOLI_ADMIN_LOGIN` is also
  the user `cron` runs scheduled jobs as, so it must stay an existing user.
- **Company** (first install only): `DOLI_COMPANY_NAME`, `DOLI_LANG`,
  `DOLI_COUNTRY`, `DOLI_CURRENCY`.
- **Versions**: `DOLI_VERSION` + `DOLI_SHA256`, `PHP_VERSION`, `DOLI_IMAGE`,
  `CADDY_VERSION`, `MARIADB_VERSION`.
- **Dolibarr / PHP**: `DOLI_PROD`, `PHP_MEMORY_LIMIT`, `UPLOAD_MAX_SIZE` (PHP
  and Caddy), `PHP_FPM_MAX_CHILDREN` and the rest of the FPM pool,
  `PHP_TIMEZONE` (PHP's `date.timezone`, on every start).
- **Mail**: `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`,
  `SMTP_PASSWORD`, `SMTP_FROM`.
- **Scheduled jobs**: `CRON_INTERVAL` (seconds, default 300).
- **Resources and logs**: `*_MEMORY_LIMIT` per service, `LOG_MAX_SIZE`,
  `LOG_MAX_FILE` (Docker log rotation).

Files:

| File                                    | Purpose                                               |
|-----------------------------------------|-------------------------------------------------------|
| `image/Dockerfile`, `image/opcache.ini` | Dolibarr image.                                       |
| `config/caddy/Caddyfile`                | Web server, TLS, security headers, blocked paths.     |
| `config/php/php.ini`                    | PHP limits, timezone, disabled functions.             |
| `config/php/fpm-pool.conf`              | PHP-FPM pool sizing, from env vars.                   |
| `scripts/setup.sh`                      | Code sync, install, upgrade.                          |
| `scripts/conf.php`                      | Writes `conf.php` from the environment.               |
| `scripts/configure.php`                 | SMTP and one-time settings.                           |
| `scripts/db-version.php`                | Database version (install/upgrade decisions).         |
| `scripts/cron.sh`, `scripts/backup.sh`  | Scheduled jobs; backups and restore.                  |

Notes:

- `conf.php` is generated: change the environment (`.env`), not the file.
- The installer (`/install`) is blocked in Caddy; installs and upgrades run from
  the command line in `setup`.
- Some PHP functions are disabled (`shell_exec`, `system`, `proc_open`...), as
  recommended by Dolibarr's security page; features that need them (such as
  the built-in database backup page) don't work — use the `backup` service.
- The IMAP and LDAP PHP extensions are not included (email collector through
  the native extension, LDAP authentication); IMAP was removed from PHP's
  core in 8.4.
- From inside the containers, the host machine is reachable as
  `host.docker.internal`.

Security
--------

- Client IP headers: PHP gets only the real client IP (as Caddy sees it) in
  `REMOTE_ADDR`, `X-Forwarded-For` and `X-Real-IP`, and no `Client-Ip`,
  `Cf-Connecting-Ip` or `X-Forwarded-Port` (a client could forge them): Dolibarr's event log
  (logins...) uses `X-Forwarded-For`, `Client-Ip` or `Cf-Connecting-Ip`.
- No default secrets: compose fails if the required passwords are missing. The
  development template uses public passwords; never use it on a server.
- PHP errors are never shown to visitors (`display_errors` off unless
  `PHP_DISPLAY_ERRORS=On`, only in the development template); they go to
  `docker compose logs`.
- Production defaults: production mode on, `conf.php` read-only, installer
  locked and blocked, documents outside the web root, PHP version not exposed,
  dotfiles and logs blocked, `X-Content-Type-Options`, `X-Frame-Options` and
  `Referrer-Policy` headers, admin password hashed with `password_hash`.
- PHP gets the real client IP in `REMOTE_ADDR` (logs, login protection) also
  behind Traefik or another proxy on a private network.
- Only Caddy (and Mailpit in development) publishes ports; the database is
  internal. `HTTP_BIND` defaults to `127.0.0.1`.
- Not included: a web application firewall, login rate limiting, or off-site
  backup copies.

Validation
----------

What was checked for this stack (2026-09-24):

- Clean start (`down -v` + `up -d`, image already built) in about 20 s: every
  service `healthy`, `setup` `Exited (0)`; a second run makes no changes.
- Login; installer, `conf/` and dotfiles `403`; API explorer and theme assets
  `200`; Spanish (Chile), CLP and Chile as company country.
- A setting changed in Dolibarr survives `setup`; changing `DOLI_URL` rewrites
  `conf.php`.
- SMTP delivered to Mailpit; scheduled jobs run (`cron_run_jobs.php`);
  backup, retention and restore.
- Upgrade: 23.0.4 installed, then `DOLI_VERSION=24.0.1` → code synced, database
  migrated (`23.0.0-24.0.0.sql`), data kept.
- HTTPS with `SITE_ADDRESS=localhost` (Caddy internal CA, HTTP/2);
  production mode.
- Overrides: Traefik v3.6 routing with no host ports, local directories
  (including backups), a module mounted in `htdocs/custom`, enabled and served.
- Not tested: issuing a real Let's Encrypt certificate (needs a public domain).

Resource usage
--------------

Idle, after a few requests: Caddy ~16 MiB, PHP-FPM ~35 MiB, MariaDB ~200 MiB,
cron and backup ~1 MiB between runs.

License
-------

[MIT](LICENSE).
