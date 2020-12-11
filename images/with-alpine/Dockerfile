FROM alpine:edge

# Switch to edge repositories for PHP 7.4
RUN sed -i -e 's/v[[:digit:]]\..*\//edge\//g' /etc/apk/repositories

RUN apk update && apk upgrade

# Configure timezones
RUN apk add tzdata && \
    cp /usr/share/zoneinfo/Europe/Paris /etc/localtime && \
    echo "Europe/Paris" >  /etc/timezone && \
    apk del tzdata
