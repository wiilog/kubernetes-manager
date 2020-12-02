#!/bin/sh

echo "Starting PHP-FPM daemon and NGINX"
php-fpm7 --allow-to-run-as-root
nginx
