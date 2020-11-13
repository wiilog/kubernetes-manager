FROM wiilog/with-wkhtmltopdf:latest

# Dependencies
RUN apk add curl

# Install web server
RUN apk add php7
RUN apk add php7-pdo php7-pdo_mysql php7-zlib \
            php7-curl php7-json php7-mbstring \
            php7-opcache php7-gd php7-intl php7-session \
            php7-tokenizer php7-iconv php-dom \
            php7-ctype php7-fpm php7-simplexml php7-xml
RUN apk add nginx
RUN apk add certbot certbot-nginx

# Copy resources
RUN mkdir /bootstrap
ADD resources/entrypoint.sh         /bootstrap
ADD resources/maintenance.sh        /bootstrap
ADD resources/php/php.ini           /etc/php7
ADD resources/fpm/php-fpm.conf      /etc/php7
ADD resources/nginx/nginx.conf      /etc/nginx
ADD resources/nginx/nossl.conf      /etc/nginx/conf.d/default.conf
ADD resources/nginx/ssl.conf        /etc/nginx/ssl.conf

# Nginx
RUN mkdir /run/nginx /run/php-fpm
RUN mkdir /etc/nginx/ssl
