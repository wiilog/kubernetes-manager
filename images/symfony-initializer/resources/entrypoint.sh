#!/bin/sh

set -e
OPTIONS="$@"

has_option() {
    MATCH="$1"

    if test "${OPTIONS#*$MATCH}" != "$OPTIONS" ; then
        return 0
    else
        return 1
    fi
}

cd /project

composer install --no-dev --optimize-autoloader --classmap-authoritative
php bin/console fos:js-routing:dump

yarn install
yarn build:only:production

SQL_HAS_TABLES="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DATABASE_NAME';"
TABLES_COUNT=$(mysql -h $DATABASE_HOST -P $DATABASE_PORT -u $DATABASE_USER -p$DATABASE_PASSWORD -sse "$SQL_HAS_TABLES")

if [ $? -ne 0 ]; then
    echo "Failed to access database with error code $?, exiting entrypoint"
    exit 1
elif [ $TABLES_COUNT = "0" ]; then
    echo "New instance, creating database"
   
    if has_option "--with-migrations"; then
        php bin/console doctrine:schema:update --force
        php bin/console doctrine:migrations:sync-metadata-storage
        php bin/console doctrine:migrations:version --add --all --no-interaction
    else
        php bin/console doctrine:schema:update --force
    fi
else
    echo "Existing instance, updating database"

    if has_option "--with-migrations"; then
        touch /tmp/migrations.sql
        php bin/console doctrine:migrations:migrate --dry-run --write-sql /tmp/migrations.sql

        if [ $(wc -c < /tmp/migrations.sql) -ne 0 ]; then
            echo "1" > /tmp/migrations

            STARTED_WAITING=$(date +"%s")
            while [ ! -f /tmp/ready ]; do
                NOW=$(date +"%s")
                WAITING_FOR=$(($NOW - $STARTED_WAITING))
                if [ "$WAITING_FOR" -gt "20" ]; then
                    echo "No instruction received in 20 seconds, proceeding with installation"
                    break
                fi

                sleep 0.1
            done
            
            php bin/console doctrine:migrations:migrate --no-interaction
        else
            echo "0" > /tmp/migrations
        fi
    fi

    php bin/console doctrine:schema:update --dump-sql
    php bin/console doctrine:schema:update --force
fi

if has_option "--with-fixtures"; then
    php bin/console doctrine:fixtures:load --append --group fixtures
    php bin/console app:update:translations
fi

php bin/console cache:clear
