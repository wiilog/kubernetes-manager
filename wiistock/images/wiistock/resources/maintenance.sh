#!/bin/sh

sed -i 's/\$APP_ENV/maintenance/g' /etc/php7/php-fpm.conf
pkill php-fpm7
php-fpm7