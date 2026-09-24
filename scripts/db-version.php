<?php
/**
 * Prints the Dolibarr version the database was installed or last upgraded to
 * (empty if the database has no Dolibarr tables yet).
 */

mysqli_report(MYSQLI_REPORT_OFF);
$db = @new mysqli(getenv('DB_HOST'), getenv('DB_USER'), getenv('DB_PASSWORD'), getenv('DB_NAME'), (int) getenv('DB_PORT'));
if ($db->connect_errno) {
    fwrite(STDERR, "Database connection failed: {$db->connect_error}\n");
    exit(1);
}
$result = $db->query(
    "SELECT value FROM llx_const WHERE name IN ('MAIN_VERSION_LAST_INSTALL', 'MAIN_VERSION_LAST_UPGRADE') AND entity = 0"
);
$version = '';
if ($result) {
    while ($row = $result->fetch_row()) {
        if ($version === '' || version_compare($row[0], $version, '>')) {
            $version = $row[0];
        }
    }
}
echo $version;
