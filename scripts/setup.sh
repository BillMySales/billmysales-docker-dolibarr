#!/bin/sh
# Installs or upgrades Dolibarr and applies the stack's environment.
#
# Runs as root on every `docker compose up` and is safe to repeat:
# - Syncs the code from the image to the code volume when DOLI_VERSION
#   changes, keeping htdocs/conf (configuration) and htdocs/custom (modules).
# - Installs Dolibarr with its CLI installer if the database is empty.
# - Upgrades the database if it is older than the code.
# - Writes conf.php from the environment (scripts/conf.php) and applies SMTP
#   and one-time initial settings (scripts/configure.php).
set -eu

CODE=/var/www/dolibarr
DOCS=/var/www/documents
STACK=/usr/local/share/stack/scripts
cd "${CODE}"

as_www() { su-exec www-data "$@"; }

# The mount points may be root-owned (e.g. new bind mounts).
chown www-data:www-data "${CODE}" "${DOCS}"

if [ "$(cat .version 2>/dev/null || true)" != "${DOLI_VERSION}" ]; then
    echo "==> Syncing Dolibarr ${DOLI_VERSION} code (was: $(cat .version 2>/dev/null || echo none))"
    find "${CODE}" -mindepth 1 -maxdepth 1 ! -name htdocs -exec rm -rf {} +
    if [ -d htdocs ]; then
        find htdocs -mindepth 1 -maxdepth 1 ! -name conf ! -name custom -exec rm -rf {} +
    fi
    cp -a /usr/src/dolibarr/. "${CODE}/"
fi

db_version="$(as_www php "${STACK}/db-version.php")"

if [ -z "${db_version}" ]; then
    echo "==> Installing Dolibarr ${DOLI_VERSION} at ${DOLI_URL}"
    rm -f htdocs/conf/conf.php "${DOCS}/install.lock"
    touch htdocs/conf/conf.php
    chown www-data:www-data htdocs/conf/conf.php
    cd htdocs/install
    # Arguments: see the $argv handling at the top of each step.
    as_www php step1.php set "${DOLI_LANG}" "${CODE}/htdocs" "${DOCS}" "${DOLI_URL}" \
        "" "" mysqli "${DB_HOST}" "${DB_NAME}" "${DB_USER}" "${DB_PASSWORD}" \
        "${DB_PORT}" llx_ 0 0 > /tmp/install-step1.log 2>&1
    as_www php step2.php set "${DOLI_LANG}" > /tmp/install-step2.log 2>&1
    as_www php step5.php 0 0 "${DOLI_LANG}" set "${DOLI_ADMIN_LOGIN}" \
        "${DOLI_ADMIN_PASSWORD}" "${DOLI_ADMIN_PASSWORD}" 1 > /tmp/install-step5.log 2>&1
    cd "${CODE}"
    db_version="$(as_www php "${STACK}/db-version.php")"
    if [ -z "${db_version}" ]; then
        echo "Install failed, installer output:" >&2
        sed 's/<[^>]*>//g' /tmp/install-step*.log | grep -v '^\s*$' | tail -40 >&2
        exit 1
    fi
elif [ "$(printf '%s\n%s\n' "${db_version}" "${DOLI_VERSION}" | sort -V | head -1)" != "${DOLI_VERSION}" ]; then
    echo "==> Upgrading database ${db_version} -> ${DOLI_VERSION}"
    touch "${DOCS}/upgrade.unlock"
    chown www-data:www-data "${DOCS}/upgrade.unlock"
    cd htdocs/install
    as_www php upgrade.php "${db_version}" "${DOLI_VERSION}" > /tmp/upgrade.log 2>&1
    as_www php upgrade2.php "${db_version}" "${DOLI_VERSION}" >> /tmp/upgrade.log 2>&1
    as_www php step5.php "${db_version}" "${DOLI_VERSION}" "${DOLI_LANG}" upgrade >> /tmp/upgrade.log 2>&1
    cd "${CODE}"
    rm -f "${DOCS}/upgrade.unlock"
    db_version="$(as_www php "${STACK}/db-version.php")"
    if [ "${db_version}" != "${DOLI_VERSION}" ]; then
        echo "Upgrade failed (database at ${db_version}), output:" >&2
        sed 's/<[^>]*>//g' /tmp/upgrade.log | grep -v '^\s*$' | tail -40 >&2
        exit 1
    fi
fi

# Version marker last: a failed sync or install is retried on the next run.
echo "${DOLI_VERSION}" > .version

echo "==> Applying environment (conf.php, SMTP)"
php "${STACK}/conf.php" htdocs/conf/conf.php
chown www-data:www-data htdocs/conf/conf.php
as_www php "${STACK}/configure.php"

echo "==> Done: Dolibarr ${DOLI_VERSION}"
echo "    URL:   ${DOLI_URL}"
echo "    Admin: ${DOLI_ADMIN_LOGIN}"
