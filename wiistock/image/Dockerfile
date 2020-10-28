FROM alpine:edge

# Switch to edge repositories for PHP 7.4
RUN sed -i -e 's/v[[:digit:]]\..*\//edge\//g' /etc/apk/repositories

RUN apk update
RUN apk upgrade

# Configure timezones
RUN apk add tzdata
RUN cp /usr/share/zoneinfo/Europe/Paris /etc/localtime
RUN echo "Europe/Paris" >  /etc/timezone
RUN apk del tzdata

# Dependencies
RUN apk add git curl mysql-client

# Install web server
RUN apk add php7
RUN apk add php7-zip php7-cli php7-pdo_mysql php7-zlib \
            php7-curl php7-json php7-mbstring php7-xml \
            php7-opcache php7-gd php7-intl php7-session \
            php7-tokenizer php7-iconv php-dom php7-pdo \
            php7-ctype php7-phar php7-fpm php7-simplexml
RUN apk add nginx
RUN apk add nodejs yarn
RUN apk add certbot certbot-nginx

# Copy resources
RUN mkdir /bootstrap
ADD resources/entrypoint.sh         /bootstrap/entrypoint.sh
ADD resources/php/php.ini           /etc/php7
ADD resources/fpm/php-fpm.conf      /etc/php7
ADD resources/nginx/default.conf    /etc/nginx/conf.d
RUN chmod +x /bootstrap/entrypoint.sh

# Install composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
RUN php -r "if (hash_file('sha384', 'composer-setup.php') === 'c31c1e292ad7be5f49291169c0ac8f683499edddcfd4e42232982d0fd193004208a58ff6f353fde0012d35fdd72bc394') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
RUN php composer-setup.php --version=1.10.16 --install-dir=bin --filename=composer
RUN php -r "unlink('composer-setup.php');"

# Nginx
RUN mkdir /run/nginx