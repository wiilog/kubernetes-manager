#!/bin/sh

sleep 5

echo "Creating certificate"
certbot --nginx \
    --agree-tos \
    --redirect \
    --email bonjour@wiilog.fr \
    --domains $DOMAIN \
    --non-interactive 

exit 0