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

execute_query() {
    mysql $2 -h $DATABASE_HOST -P $DATABASE_PORT -u $DATABASE_USER -p$DATABASE_PASSWORD -sse "$1"
}

prepare_project() {
    # Extract vendor and node_modules from cache if it exists
    if [ -f /cache/cache.tar.gz ]; then
        tar xzf /cache/cache.tar.gz
    fi

    composer install \
        --no-dev \
        --optimize-autoloader \
        --classmap-authoritative \
        --no-scripts \
        --no-ansi &
        
    yarn install &

    wait
}

install_symfony() {
    TABLE_COUNT=$(execute_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DATABASE_NAME';")

    if [ $? -ne 0 ]; then
        echo "Failed to access database with error code $?, aborting installation"
        exit 1
    elif [ "$TABLE_COUNT" = "0" ]; then
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
            php bin/console doctrine:migrations:migrate --no-interaction --dry-run --write-sql /tmp/migrations.sql

            if [ $(wc -c < /tmp/migrations.sql) -ne 0 ]; then
                echo -n 1 > /tmp/migrations

                STARTED_WAITING=$(date +%s)
                while [ ! -f /tmp/ready ]; do
                    NOW=$(date +%s)
                    WAITING_FOR=$(($NOW - $STARTED_WAITING))
                    if [ "$WAITING_FOR" -gt "20" ]; then
                        echo "No instruction received in 20 seconds, proceeding with installation"
                        break
                    fi

                    sleep 0.1
                done
                
                php bin/console doctrine:migrations:migrate --no-interaction
            else
                echo -n 0 > /tmp/migrations
            fi
        else
            echo -n 0 > /tmp/migrations
        fi

        php bin/console doctrine:schema:update --dump-sql
        php bin/console doctrine:schema:update --force
    fi

    if has_option "--with-fixtures"; then
        php bin/console doctrine:fixtures:load --append --group fixtures
        php bin/console app:update:translations
    fi

    php bin/console cache:clear
    php bin/console cache:warmup
}

install_yarn() {
    if has_option "--with-fos"; then
        php bin/console fos:js-routing:dump
    fi

    FONT_FAMILY=$(execute_query "SELECT value FROM parametrage_global WHERE label = 'FONT FAMILY';" $DATABASE_NAME 2> /dev/null || true)
    if [ -n "$FONT_FAMILY" ]; then
        echo "Using font family \"$FONT_FAMILY\""
        echo "\$mainFont: "$FONT_FAMILY";" > /project/assets/scss/_customFont.scss
    else
        echo "Using default font family"
        echo "" > /project/assets/scss/_customFont.scss
    fi

    yarn build:only:production || true
    yarn production || true
}

cd /project

prepare_project
install_symfony &
install_yarn    &
wait
