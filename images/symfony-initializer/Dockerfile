FROM wiilog/wiistock:latest

RUN apk del wkhtmltopdf
RUN apk del nginx php7-fpm
RUN apk del certbot certbot-nginx

RUN apk add git mysql-client
RUN apk add php7-cli php7-phar
RUN apk add yarn

# Install composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
RUN php -r "if (hash_file('sha384', 'composer-setup.php') === 'c31c1e292ad7be5f49291169c0ac8f683499edddcfd4e42232982d0fd193004208a58ff6f353fde0012d35fdd72bc394') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
RUN php composer-setup.php --version=1.10.16 --install-dir=bin --filename=composer
RUN php -r "unlink('composer-setup.php');"

ADD resources/entrypoint.sh /bootstrap/entrypoint.sh