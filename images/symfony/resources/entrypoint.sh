#!/bin/sh

if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo "Obtaining certificate"
    certbot --standalone certonly \
        --agree-tos \
        --redirect \
        --email bonjour@wiilog.fr \
        --domains $DOMAIN \
        --non-interactive
else
    echo "Using existing certificate"
fi

mkdir -p /etc/nginx/ssl
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/nginx/ssl
cp /etc/letsencrypt/live/$DOMAIN/cert.pem /etc/nginx/ssl

echo "Starting nginx and fpm daemons"
php-fpm7 --allow-to-run-as-root
nginx

sleep infinity