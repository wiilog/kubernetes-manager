#!/bin/sh

copy_certificates() {
    mv /etc/nginx/ssl.conf /etc/nginx/conf.d/default.conf
    cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/nginx/ssl
    cp /etc/letsencrypt/live/$DOMAIN/cert.pem /etc/nginx/ssl
}

generate_certificates() {
    sleep 15
    
    echo "Obtaining certificate"
    certbot certonly \
        --nginx \
        --agree-tos \
        --redirect \
        --email bonjour@wiilog.fr \
        --domains $DOMAIN \
        --non-interactive

    copy_certificates

    nginx -s reload
}

if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    generate_certificates &
else
    echo "Using existing certificate"
    copy_certificates
fi


echo "Starting PHP-FPM daemon and NGINX"
php-fpm7 --allow-to-run-as-root --force-stderr
nginx
