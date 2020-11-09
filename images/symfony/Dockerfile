FROM surnet/alpine-wkhtmltopdf:3.12-0.12.6-full as wkhtmltopdf
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
ADD resources/entrypoint.sh         /bootstrap/entrypoint.sh
ADD resources/maintenance.sh        /bootstrap/maintenance.sh
ADD resources/certificate.sh        /bootstrap/certificate.sh
ADD resources/php/php.ini           /etc/php7
ADD resources/fpm/php-fpm.conf      /etc/php7
ADD resources/nginx/default.conf    /etc/nginx/conf.d

# Nginx
RUN mkdir /run/nginx

# WKHTMLToPDF (copied from https://github.com/Surnet/docker-wkhtmltopdf)
RUN apk add --no-cache \
    libstdc++ \
    libx11 \
    libxrender \
    libxext \
    libssl1.1 \
    ca-certificates \
    fontconfig \
    freetype \
    ttf-dejavu \
    ttf-droid \
    ttf-freefont \
    ttf-liberation \
    ttf-ubuntu-font-family \
    && apk add --no-cache --virtual .build-deps \
    msttcorefonts-installer \
    && update-ms-fonts \
    && fc-cache -f \
    && rm -rf /tmp/* \
    && apk del .build-deps

# Copy wkhtmltopdf files from docker-wkhtmltopdf image
COPY --from=wkhtmltopdf /bin/wkhtmltopdf /usr/bin/wkhtmltopdf