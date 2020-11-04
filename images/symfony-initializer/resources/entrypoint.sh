#!/bin/sh

set -e
OPTIONS="$@"

contains() {
    STRING="$1"
    MATCH="$2"

    if test "${STRING#*$MATCH}" != "$STRING"; then
        return 0
    else
        return 1
    fi
}

cd /project

composer install --no-dev --optimize-autoloader
touch var/log/prod.log

yarn install
yarn build

php bin/console cache:warmup

if [ contains "$OPTIONS" "with-migrations" ]; then
    SQL_HAS_TABLES="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DATABASE_NAME';"
    TABLES_COUNT=$(mysql -h $DATABASE_HOST -P $DATABASE_PORT -u $DATABASE_USER -p$DATABASE_PASSWORD -sse "$SQL_HAS_TABLES")

    if [ $? -ne 0 ]; then
        echo "Failed to access database with error code $?, exiting entrypoint"
        exit 1
    elif [ $TABLES_COUNT = "0" ]; then
        echo "New instance, creating database"
        php bin/console doctrine:schema:update --force
        php bin/console doctrine:migrations:sync-metadata-storage
        php bin/console doctrine:migrations:version --add --all --no-interaction
    else
        echo "Existing instance, updating database"
        
        # TODO: dry run and wait

        php bin/console doctrine:migrations:migrate --no-interaction
        php bin/console doctrine:schema:update --dump-sql
        php bin/console doctrine:schema:update --force
    fi
else
    php bin/console doctrine:schema:update --dump-sql
    php bin/console doctrine:schema:update --force
fi

if [ contains "$OPTIONS" "with-fixtures" ]; then
    php bin/console doctrine:fixtures:load --append --group fixtures
    php bin/console app:update:translations
fi
