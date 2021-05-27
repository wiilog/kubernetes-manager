#!/bin/sh

set -e

create_project() {
    cd /project

    composer install \
        --no-dev \
        --optimize-autoloader \
        --classmap-authoritative \
        --no-ansi

    yarn install
}

rm -rf /cache/*.tar.gz

create_project

command time -f "Compressed vendor folders in %es" \
tar czf /cache/cache.tar.gz vendor node_modules

rm -rf vendor node_modules

command time -f "Estimated extraction time %es" \
tar xzf /cache/cache.tar.gz
