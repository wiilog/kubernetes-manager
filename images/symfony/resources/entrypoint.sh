#!/bin/sh

echo "Starting nginx and fpm daemons"
php-fpm7
nginx

sleep infinity