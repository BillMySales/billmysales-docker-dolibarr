#!/bin/sh
# Runs Dolibarr's scheduled jobs (scripts/cron/cron_run_jobs.php) every
# CRON_INTERVAL seconds, as the DOLI_ADMIN_LOGIN user.
set -u

HEARTBEAT=/tmp/cron-heartbeat
CODE=/var/www/dolibarr

case "${1:-run}" in
    health)
        # Healthy if the loop completed a pass within 3 intervals.
        [ -n "$(find "${HEARTBEAT}" -mmin -"$(( (CRON_INTERVAL * 3 + 59) / 60 ))" 2>/dev/null)" ]
        exit
        ;;
esac

cron_key() {
    php -r 'define("NOSESSION", 1); define("NOREQUIREHTML", 1);
        require "/var/www/dolibarr/htdocs/master.inc.php"; echo getDolGlobalString("CRON_KEY");' 2>/dev/null
}

echo "==> Running Dolibarr scheduled jobs every ${CRON_INTERVAL}s"
while :; do
    key="$(cron_key || true)"
    if [ -n "${key}" ]; then
        php "${CODE}/scripts/cron/cron_run_jobs.php" "${key}" "${DOLI_ADMIN_LOGIN}" > /tmp/cron-last.log 2>&1 \
            || { echo "Scheduled jobs failed:" >&2; tail -5 /tmp/cron-last.log >&2; }
    fi
    touch "${HEARTBEAT}"
    sleep "${CRON_INTERVAL}"
done
