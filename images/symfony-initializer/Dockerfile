FROM wiilog/symfony:latest

RUN apk del nginx php7-fpm
RUN apk add tar mysql-client yarn php7-cli php7-phar

# Install composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
RUN php -r "if (hash_file('sha384', 'composer-setup.php') === '756890a4488ce9024fc62c56153228907f1545c228516cbf63f885e036d37e9a59d27d63f46af1d4d07ee0f76181c7d3') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
RUN php composer-setup.php --version=1.10.17 --install-dir=bin --filename=composer
RUN php -r "unlink('composer-setup.php');"

ADD resources/entrypoint.sh /bootstrap/entrypoint.sh
RUN chmod +x /bootstrap/entrypoint.sh