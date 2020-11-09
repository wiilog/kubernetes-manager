#!/bin/sh

echo "Starting nginx and fpm daemons"
php-fpm7 --allow-to-run-as-root
nginx

# Obtaining certificate
# certbot --nginx \
#     --agree-tos \
#     --redirect \
#     --email bonjour@wiilog.fr \
#     --domains $DOMAIN \
#     --non-interactive 

sleep infinity