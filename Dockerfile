FROM ubuntu:latest
LABEL maintainer="support@uvdesk.com"

ENV DEBIAN_FRONTEND=noninteractive
ENV GOSU_VERSION=1.11

# Base packages + PHP 8.1 + Apache (NO mysql-server here)
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get install -y software-properties-common && \
    add-apt-repository -y ppa:ondrej/php && \
    apt-get update && \
    apt-get -y install \
        adduser \
        curl \
        wget \
        git \
        unzip \
        apache2 \
        php8.1 \
        libapache2-mod-php8.1 \
        php8.1-common \
        php8.1-xml \
        php8.1-imap \
        php8.1-mysql \
        php8.1-mailparse \
        php8.1-curl \
        ca-certificates \
        gnupg2 dirmngr && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# (Optional) non-root app user – not strictly needed for Railway, we’ll run Apache as www-data
RUN adduser uvdesk --disabled-password --gecos ""

# Apache configs from repo
COPY ./.docker/config/apache2/env /etc/apache2/envvars
COPY ./.docker/config/apache2/httpd.conf /etc/apache2/apache2.conf
COPY ./.docker/config/apache2/vhost.conf /etc/apache2/sites-available/000-default.conf

# App code + entrypoint
COPY ./.docker/bash/uvdesk-entrypoint.sh /usr/local/bin/
COPY . /var/www/uvdesk/

# Enable PHP + rewrite; allow entrypoint to run
RUN a2enmod php8.1 rewrite && \
    chmod +x /usr/local/bin/uvdesk-entrypoint.sh

# Install gosu (kept for parity; not required by our entrypoint)
RUN dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" && \
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch" && \
    wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc" && \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 && \
    gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu && \
    gpgconf --kill all && \
    chmod +x /usr/local/bin/gosu && \
    gosu nobody true && \
    rm -rf /usr/local/bin/gosu.asc

# Composer
RUN wget -O /usr/local/bin/composer.php "https://getcomposer.org/installer" && \
    actualSig="$(wget -q -O - https://composer.github.io/installer.sig)" && \
    currentSig="$(sha384sum /usr/local/bin/composer.php | awk '{print $1}')" && \
    if [ "$currentSig" != "$actualSig" ]; then echo "Composer signature mismatch" && exit 1; fi && \
    php /usr/local/bin/composer.php --quiet --filename=/usr/local/bin/composer && \
    chmod +x /usr/local/bin/composer && rm -f /usr/local/bin/composer.php

WORKDIR /var/www/uvdesk

# PHP deps (optimized)
RUN composer install --no-dev --optimize-autoloader

# Ownership for Apache (www-data) to write caches/uploads
RUN chown -R www-data:www-data /var/www/uvdesk && \
    chmod -R 775 /var/www/uvdesk/var \
                 /var/www/uvdesk/config \
                 /var/www/uvdesk/public \
                 /var/www/uvdesk/migrations || true

# Warm cache (ignore first-run misses)
RUN composer dump-autoload --optimize && \
    php bin/console cache:clear --env=prod --no-debug || true

# --- Railway-specific: listen on $PORT and silence ServerName warning
RUN printf 'Listen ${PORT:-8080}\n' > /etc/apache2/ports.conf && \
    sed -i 's#<VirtualHost \*:80>#<VirtualHost *:${PORT:-8080}>#' /etc/apache2/sites-available/000-default.conf && \
    printf '\nServerName ${APP_URL:-localhost}\n' >> /etc/apache2/apache2.conf

ENV APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data

# Entrypoint hands off to Apache in foreground
ENTRYPOINT ["/usr/local/bin/uvdesk-entrypoint.sh"]
CMD ["apachectl","-D","FOREGROUND"]
