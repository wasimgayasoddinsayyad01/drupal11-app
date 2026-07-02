# syntax=docker/dockerfile:1

# ---- Stage 1: Composer dependencies ----------------------------------
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
# --ignore-platform-reqs: this stage only resolves/downloads packages, it never
# executes Drupal, so the composer:2 image not having gd/etc. doesn't matter.
# The actual gd extension IS installed in the runtime stage below, where it's needed.
RUN composer install --no-dev --prefer-dist --no-progress --no-interaction --no-scripts --ignore-platform-reqs
COPY . .
RUN composer install --no-dev --prefer-dist --no-progress --no-interaction --ignore-platform-reqs

# ---- Stage 2: Runtime (PHP-FPM + nginx via supervisor) -----------------
FROM php:8.3-fpm-alpine AS runtime

RUN apk add --no-cache nginx supervisor mysql-client icu-dev libpng-dev libzip-dev \
    && docker-php-ext-install pdo_mysql gd opcache intl zip

# Recommended opcache settings for Drupal in production
RUN { \
    echo 'opcache.memory_consumption=192'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=20000'; \
    echo 'opcache.validate_timestamps=0'; \
    echo 'opcache.enable_cli=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

WORKDIR /var/www/html
COPY --from=vendor /app ./

COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Drupal needs write access to sites/default/files at runtime.
# On ECS this directory should be an EFS mount, not container-local storage,
# so uploaded files survive deploys and are shared across tasks.
RUN chown -R www-data:www-data web/sites/default/files 2>/dev/null || true

EXPOSE 8080
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
