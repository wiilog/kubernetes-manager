FROM wiilog/with-wkhtmltopdf:latest

# Install web server
RUN apk add nginx php7 php7-pdo php7-pdo_mysql php7-zlib \
            curl php7-curl php7-json php7-mbstring php7-xml \
            php7-opcache php7-gd php7-intl php7-session \
            php7-tokenizer php7-iconv php-dom php7-mysqli \
            php7-ctype php7-fpm php7-simplexml php7-fileinfo \
            php7-xmlreader

# Copy resources
RUN mkdir /bootstrap
ADD resources/entrypoint.sh         /bootstrap
ADD resources/maintenance.sh        /bootstrap
ADD resources/php/php.ini           /etc/php7
ADD resources/fpm/php-fpm.conf      /etc/php7
ADD resources/nginx/nginx.conf      /etc/nginx
ADD resources/nginx/default.conf    /etc/nginx/conf.d
RUN chmod +x /bootstrap/*.sh

# Socket files
RUN mkdir /run/nginx /run/php-fpm
