#!/bin/bash

# We wait until MariaDB (the Db) is on, to synchronize with WordPress
MAX_RETRIES=2
if [ "$TEST_MODE" = "1" ]; then
    MAX_RETRIES=5
fi

COUNT=0
while ! mysqladmin ping -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" --silent; do
    sleep 2
    COUNT=$((COUNT+1))
    if [ $COUNT -eq $MAX_RETRIES ]; then
        echo "ERROR: MariaDB not available."
        exit 1
    fi
done

echo "--- DB is available"

# We check if "wp" (WP-CLI) already exist
# If not, we dl it. WP-CLI permit auto config and installation of WP
if [ ! -f /usr/local/bin/wp ]; then
    echo "Installing WP-CLI..."
    curl -o wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
fi

# We check if wp-config.php exist (one of the main file of WordPress)
# If not, we create a new one with WP-CLI with env variable parameters
# --skip-check: to avoid testing the DB (time saving)
# --allow-root: necessary because the script runs with root inside the container
# --path: to precise WordPress path (wp_path)
if [ ! -f wp-config.php ]; then
    echo "--- Making wp-config.php"
    wp config create \
        --dbname="${DB_NAME}" \
        --dbuser="${DB_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="${DB_HOST}" \
        --skip-check \
        --allow-root \
        --path=/var/www/html
    echo "OK: wp-config.php created!"
fi

# We check if WP is already installed
# If not, we launch the installation (admin creation too)
# After installation, we create another user (as required from the subject)
if ! wp core is-installed --allow-root --path=/var/www/html; then
    echo "--- Installation of Wordpress"
    
    # Install WordPress
    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="My Inception Site" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root \
        --path=/var/www/html

    # Create additional user
    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=author \
        --user_pass="${WP_USER_PASSWORD}" \
        --allow-root \
        --path=/var/www/html

    echo "--- WordPress OK"
else
    echo "--- WordPress has been already installed before"
fi

# We start PHP-FPM and it stays on foreground
# If PHP-FPM stops, the containers stops too!!
exec php-fpm8.2 --nodaemonize