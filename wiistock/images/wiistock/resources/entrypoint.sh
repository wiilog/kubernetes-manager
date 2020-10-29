#!/bin/sh

echo "Starting nginx and fpm daemons"
php-fpm7
nginx

echo "Creating certificate"
certbot --nginx \
    --agree-tos \
    --redirect \
    --email bonjour@wiilog.fr \
    --domains $DOMAIN \
    --non-interactive 

sleep infinity