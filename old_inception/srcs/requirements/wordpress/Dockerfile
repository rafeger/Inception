FROM debian:bookworm

# We install PHP-FPM and php extensions useful to Wordpress
# php-fpm: PHP FastCGI server (Wordpress runs with it)
# php-mysql: connector MySQL/MariaDB
# php-curl, json, mbstring, opcache, zip: useful modules for Wordpress/plugins
# curl, tar, unzip: to download and extract WP + WP-CLI
# iputils-ping: to test connectivity (for debug, not mandatory)
# mariadb-client : to geet mysql and mysqladmin, necessary to wait for DB
RUN apt update && apt-get upgrade -y  
RUN apt install -y php \
    php-fpm \
    php-mysqli \
    php-curl \
    php-json \
    php-mbstring \
    php-opcache \
    php-zip \
    curl \
    tar \
    unzip \
    iputils-ping \
    mariadb-client

# We set working directory (mount wp_data)
WORKDIR /var/www/html

# We download last version of WP and extract into workdir
RUN curl -o /wordpress.tar.gz https://wordpress.org/latest.tar.gz && \
    tar -xzf /wordpress.tar.gz --strip-components=1 -C . && \
    rm /wordpress.tar.gz

# We copy the script inside the image
COPY ./conf/setup_wordpress.sh /setup_wordpress.sh

RUN chmod +x /setup_wordpress.sh

# Change owner of WP directories as www-data (standard user on Debian)
RUN chown -R www-data:www-data /var/www/html

# We modify PHP-FPM config
# - We listen on all interfaces, port 9000 (let other containers connect (on Docker networkd only))
# - We execute scripts PHP with the right user
# - let PHP-FPM transmit env variables, if not they will be erased
RUN sed -i 's|^listen = .*|listen = 0.0.0.0:9000|' /etc/php/*/fpm/pool.d/www.conf && \
    sed -i 's|^user = .*|user = www-data|' /etc/php/*/fpm/pool.d/www.conf && \
    sed -i 's|^group = .*|group = www-data|' /etc/php/*/fpm/pool.d/www.conf && \
    sed -i 's|;clear_env = no|clear_env = no|' /etc/php/*/fpm/pool.d/www.conf

# To be sure PHP-FPM directory is created (else crash at running)
RUN mkdir -p /run/php

# We expose 9000 (WP listen on port 9000 (FastCGI))
EXPOSE 9000

# When Wordpress start, we launch setup_wordpress.sh
CMD ["/setup_wordpress.sh"]