#!/bin/sh

export APP_ENV=prod

git clone ${repository} /project
cd /project
composer install --no-dev --optimize-autoloader
yarn install
yarn build

echo "Starting apache"
nginx -g "daemon off;"