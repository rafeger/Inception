#!/bin/sh

# Launch MariaDB on background, recommanded way with mysqld_safe because it has some features such as restarting the server when error occurs
# The "&" let the script continue while MariaDB start
mysqld_safe &

# Max tries
# Waiting loop to check if MariaDB answering (mysqladmin ping)
# So we block the script until the DB is ready
MAX_RETRIES=2
if [ "$TEST_MODE" = "1" ]; then
    MAX_RETRIES=5
fi

COUNT=0
until mysqladmin ping >/dev/null 2>&1 || [ $COUNT -eq $MAX_RETRIES ]; do
    sleep 5
    echo "--- MariaDB initialization..."
    COUNT=$((COUNT+1))
done

if [ $COUNT -eq $MAX_RETRIES ]; then
    echo "ERROR: MariaDB did not start."
    exit 1
fi

echo "DB is ON"

# Create the DB and create USER of the db, available from % (all host (ip adresses)) | means it can connect from everywhere (all containers in our cases)
# If we don't, only localhost we'll be valid
mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;"
mysql -u root -e "CREATE USER IF NOT EXISTS \`${DB_USER}\`@'%' IDENTIFIED BY '${DB_PASSWORD}';"

# Give all permissions of the base to the created user and reload the privileges settings
mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO \`${DB_USER}\`@'%';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Change the root password (which is "root" by default)
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';"

echo "--- DB setup OK"

# We stop MariaDB that we launch in background, because we'll relaunch again as main process of the container just after
mysqladmin -u root -p${DB_ROOT_PASSWORD} shutdown
echo "--- Shutdown of MariaDB server"

# We relaunch MariaDB as the main process (with the previous settings that we settled)
exec mysqld_safe