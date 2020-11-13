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
