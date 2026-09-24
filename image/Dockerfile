# Dolibarr ERP & CRM on the official PHP-FPM Alpine image.
#
# The release's htdocs/ and scripts/ are extracted to /usr/src/dolibarr. The
# stack's `setup` service syncs them to the code volume whenever the version
# changes (keeping conf/ and custom/) and runs Dolibarr's upgrade scripts, so
# upgrading Dolibarr means changing DOLI_VERSION.
# Built on php:<ver>-fpm-alpine: the vendor image (dolibarr/dolibarr) only
# ships Apache and an older PHP.

ARG PHP_VERSION=8.5
FROM php:${PHP_VERSION}-fpm-alpine

# PHP extensions required by Dolibarr (curl, dom, mbstring, xml, openssl and
# opcache are already in the base image).
RUN set -eux; \
    apk add --no-cache su-exec; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS freetype-dev icu-dev libjpeg-turbo-dev libpng-dev \
        libwebp-dev libzip-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" calendar gd intl mysqli zip; \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
            | tr ',' '\n' | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache --virtual .dolibarr-rundeps $runDeps; \
    apk del --no-network .build-deps; \
    php -m | grep -qi -e '^gd$' -e '^intl$'

COPY opcache.ini /usr/local/etc/php/conf.d/opcache-recommended.ini

# Dolibarr release archive: https://github.com/Dolibarr/dolibarr/releases
# DOLI_SHA256 verifies it; leave it empty to skip the check.
ARG DOLI_VERSION=24.0.1
ARG DOLI_SHA256=cd5cb03c3f927007c7e4c63a02ebdebdcf81efd378603729bbcf6991ffa1b9c4
RUN set -eux; \
    curl -fsSL -o /tmp/dolibarr.tar.gz \
        "https://github.com/Dolibarr/dolibarr/archive/refs/tags/${DOLI_VERSION}.tar.gz"; \
    if [ -n "${DOLI_SHA256}" ]; then echo "${DOLI_SHA256}  /tmp/dolibarr.tar.gz" | sha256sum -c -; fi; \
    mkdir -p /usr/src/dolibarr; \
    tar -xzf /tmp/dolibarr.tar.gz -C /usr/src/dolibarr --strip-components=1 \
        "dolibarr-${DOLI_VERSION}/htdocs" "dolibarr-${DOLI_VERSION}/scripts"; \
    rm /tmp/dolibarr.tar.gz; \
    echo "${DOLI_VERSION}" > /usr/src/dolibarr/.version; \
    chown -R www-data:www-data /usr/src/dolibarr

# Mount points for the code and documents volumes, owned by www-data.
RUN mkdir -p /var/www/dolibarr /var/www/documents \
    && chown www-data:www-data /var/www/dolibarr /var/www/documents

ENV DOLI_VERSION=${DOLI_VERSION}
WORKDIR /var/www/dolibarr/htdocs
