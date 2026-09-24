<?php
/**
 * Applies the stack's environment to Dolibarr's settings (llx_const). Run by
 * setup.sh (as www-data) on every `docker compose up`.
 *
 * - SMTP settings follow SMTP_* when SMTP_HOST is set.
 * - Initial settings (language, company country and name, currency, scheduled
 *   jobs module) are applied once (marker DOCKER_STACK_INITIALIZED); later
 *   changes in Dolibarr are kept.
 */

define('NOSESSION', 1);
define('NOREQUIREHTML', 1);
define('NOREQUIREAJAX', 1);
require '/var/www/dolibarr/htdocs/master.inc.php';
require_once DOL_DOCUMENT_ROOT . '/core/lib/admin.lib.php';

$set = static function (string $name, $value) use ($db, $conf): void {
    if ((string) getDolGlobalString($name) !== (string) $value) {
        dolibarr_set_const($db, $name, $value, 'chaine', 0, '', $conf->entity);
        echo "    {$name} updated\n";
    }
};

// SMTP. SMTP_SECURE: tls (STARTTLS), ssl (implicit TLS), none or empty.
if (getenv('SMTP_HOST')) {
    $secure = strtolower((string) getenv('SMTP_SECURE'));
    $set('MAIN_MAIL_SENDMODE', 'smtps');
    $set('MAIN_MAIL_SMTP_SERVER', getenv('SMTP_HOST'));
    $set('MAIN_MAIL_SMTP_PORT', getenv('SMTP_PORT') ?: 587);
    $set('MAIN_MAIL_EMAIL_STARTTLS', $secure === 'tls' ? 1 : 0);
    $set('MAIN_MAIL_EMAIL_TLS', $secure === 'ssl' ? 1 : 0);
    $set('MAIN_MAIL_SMTPS_ID', (string) getenv('SMTP_USER'));
    $set('MAIN_MAIL_SMTPS_PW', (string) getenv('SMTP_PASSWORD'));
    if (getenv('SMTP_FROM')) {
        $set('MAIN_MAIL_EMAIL_FROM', getenv('SMTP_FROM'));
    }
}

// Initial settings, once.
if (!getDolGlobalString('DOCKER_STACK_INITIALIZED')) {
    echo "==> Initial settings\n";
    $set('MAIN_LANG_DEFAULT', getenv('DOLI_LANG') ?: 'es_CL');
    $set('MAIN_INFO_SOCIETE_NOM', getenv('DOLI_COMPANY_NAME') ?: 'Dolibarr');
    $set('MAIN_MONNAIE', getenv('DOLI_CURRENCY') ?: 'CLP');

    $countryCode = strtoupper(getenv('DOLI_COUNTRY') ?: 'CL');
    $country = $db->fetch_object($db->query(
        "SELECT rowid, code, label FROM " . MAIN_DB_PREFIX . "c_country WHERE code = '" . $db->escape($countryCode) . "'"
    ));
    if ($country) {
        $set('MAIN_INFO_SOCIETE_COUNTRY', $country->rowid . ':' . $country->code . ':' . $country->label);
        activateModulesRequiredByCountry($country->code);
    }

    // Scheduled jobs, run by the `cron` service.
    $user = new User($db);
    $user->fetch(0, getenv('DOLI_ADMIN_LOGIN') ?: 'admin');
    $user->loadRights();
    $result = activateModule('modCron');
    if (!empty($result['errors'])) {
        fwrite(STDERR, implode("\n", $result['errors']) . "\n");
        exit(1);
    }
    if (!getDolGlobalString('CRON_KEY')) {
        $set('CRON_KEY', bin2hex(random_bytes(16)));
    }

    $set('DOCKER_STACK_INITIALIZED', gmdate('Y-m-d\TH:i:s\Z'));
}
