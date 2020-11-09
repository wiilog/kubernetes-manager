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

composer install --no-dev --optimize-autoloader
touch var/log/prod.log

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
    
    # Build must be ran after because of custom fonts generation
    yarn install
    yarn build
else
    yarn install
    yarn build

    echo "Existing instance, updating database"
    
    # TODO: dry run and wait

    if has_option "--with-migrations"; then
        php bin/console doctrine:migrations:migrate --no-interaction
        php bin/console doctrine:schema:update --dump-sql
        php bin/console doctrine:schema:update --force
    else
        php bin/console doctrine:schema:update --dump-sql
        php bin/console doctrine:schema:update --force
    fi
fi

if has_option "--with-fixtures"; then
    php bin/console doctrine:fixtures:load --append --group fixtures
fi

php bin/console app:update:translations
php bin/console cache:clear
php bin/console cache:warmup