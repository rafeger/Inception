FROM debian:bookworm

# Installation of some packages:
# nginx: the web server
# openssl: to generate SSL certificate
# curl and vim: for debug (optionnals)
RUN apt update && \
    apt install -y nginx openssl curl vim && \
    rm -rf /var/lib/apt/lists/*

# Create folder (inside container) to store certificats
# rsa:4096 bits to secure data (encryption) | x509 format to the CTF | sha256 (hash) | 365 days OK | nodes: no password required
# subj: intels to fill automatically the certificate
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -newkey rsa:4096 -x509 -sha256 -days 365 -nodes \
        -out /etc/nginx/ssl/fpaulas-.crt \
        -keyout /etc/nginx/ssl/fpaulas-.key \
        -subj "/C=FR/ST=Paris/L=Paris/O=42 School/OU=fpaulas-/CN=fpaulas-.42.fr"

# We replace nginx default config file by our own
COPY conf/nginx.conf /etc/nginx/nginx.conf

# To be sure our working directory is created, change owner by www-data (user which Nginx uses to run)
RUN mkdir -p /var/www/html && \
    chown -R www-data:www-data /var/www/html && \
    chmod 755 /var/www/html

# We expose https listening port (443)
EXPOSE 443

# We runs nginx on foreground (or Docker would think the container is terminated)
CMD ["nginx", "-g", "daemon off;"]