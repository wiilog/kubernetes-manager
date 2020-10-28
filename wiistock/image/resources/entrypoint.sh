#!/bin/sh

SQL_HAS_TABLES="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DATABASE_NAME';"

cd /project
composer install --no-dev --optimize-autoloader

if [ $(mysql -B --disable-column-names -h $DATABASE_HOST -P $DATABASE_PORT -u $DATABASE_USER -p$DATABASE_PASSWORD -e "$SQL_HAS_TABLES") -gt 0 ]; then
    echo "New instance, creating database"
    php bin/console doctrine:schema:update –-force
    php bin/console doctrine:migrations:version –-add --all --no-interaction
else
    echo "Existing instance, updating database"
    php bin/console doctrine:migrations:migrate --no-interaction
    php bin/console doctrine:schema:update –-dump-sql
    php bin/console doctrine:schema:update –-force
fi

php bin/console doctrine:fixtures:load –-append –-group=fixtures
php bin/console app:update:translations

yarn install
yarn build

php bin/console cache:clear
php bin/console cache:warmup

echo "Starting nginx daemon"
nginx

echo "Creating certificate"
certbot --nginx \
    --non-interactive \
    --redirect
    --agree-tos \
    --email bonjour@wiilog.fr \
    --domains $DOMAIN

sleep infinity