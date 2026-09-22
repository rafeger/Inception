# Indication of which image we'll use to deploy our container
FROM debian:bookworm

# We install MariaDB server package
RUN apt-get update && apt-get upgrade -y && \
    apt install -y mariadb-server && apt clean

# We create folders manually (to be sure they are created) to stock sockets & PID, data directory, logs
# The chown is to give mysql system user, the property of those folders
# If we don't, MariaDB crash with permission denied
RUN mkdir -p /run/mysqld /var/lib/mysql /var/log/mariadb && \
    chown -R mysql:mysql /run/mysqld /var/lib/mysql /var/log/mariadb

# We initalize the base skeleton (mysql, performance_schema, etc.)
# It's like a "low level" of a first launch (executed when we build)
RUN mysql_install_db --user=mysql --datadir=/var/lib/mysql

# Copy database.cnf (overload of MariaDB config) and setup_db.sh (script to configure everything) inside the image
COPY ./conf/database.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY ./conf/setup_db.sh /setup_db.sh

RUN chmod +x ./setup_db.sh

# At the container's startup, we execute setup_db.sh, which replace the default CMD of MariaDB image (which launch mysqld directly)
ENTRYPOINT ["sh", "./setup_db.sh"]