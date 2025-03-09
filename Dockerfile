# PHP versions support:
# +--------+ -----------------+----------------------+------------------------+
# | Branch | Initial Releasae | Active Support Until | Security Support Until |
# +--------+ -----------------+----------------------+------------------------+
# | 8.1    | Nov 25, 2021     | Nov 25, 2023         | Nov 25, 2024           |
# | 8.2    | Dec  8, 2022     | Dec  8, 2024         | Dec  8, 2025           |
# | 8.3    | Nov 23, 2023     | Nov 23, 2025         | Nov 23, 2026           |
# +--------+ -----------------+----------------------+------------------------+
# - https://www.php.net/supported-versions.php
# - https://php.watch/versions
#
# Container image source:
# - https://hub.docker.com/_/php/tags?page=1&name=8.3-apache-bookworm

FROM composer:2.8.6 as composer
FROM php:8.4-apache-bookworm as base

RUN sed -i -e '/^ServerTokens/s/^.*$/ServerTokens Prod/g'                     \
  -e '/^ServerSignature/s/^.*$/ServerSignature Off/g'                \
  /etc/apache2/conf-available/security.conf

RUN echo "expose_php=Off" > /usr/local/etc/php/conf.d/php-hide-version.ini

RUN apt update                                                             && \
  apt install -y --no-install-recommends libonig-dev git unzip             && \
  apt install -y tzdata

RUN docker-php-ext-install pdo_mysql mysqli mbstring                       && \
  a2enmod rewrite ssl

FROM base as yourls

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

ARG UPSTREAM_VERSION=1.9.2
ENV YOURLS_PACKAGE https://github.com/YOURLS/YOURLS/archive/${UPSTREAM_VERSION}.tar.gz

RUN mkdir -p /opt/yourls                                                   && \
  curl -sSL ${YOURLS_PACKAGE} -o /tmp/yourls.tar.gz                      && \
  tar xf /tmp/yourls.tar.gz --strip-components=1 --directory=/opt/yourls && \
  rm -rf /tmp/yourls.tar.gz

WORKDIR /opt/yourls

ADD https://github.com/YOURLS/timezones/archive/master.tar.gz                 \
  /opt/timezones.tar.gz
ADD https://github.com/dgw/yourls-dont-track-admins/archive/master.tar.gz     \
  /opt/dont-track-admins.tar.gz
ADD https://github.com/timcrockford/302-instead/archive/master.tar.gz         \
  /opt/302-instead.tar.gz
ADD https://github.com/YOURLS/force-lowercase/archive/master.tar.gz           \
  /opt/force-lowercase.tar.gz
ADD https://github.com/guessi/yourls-mobile-detect/archive/refs/tags/3.0.0.tar.gz \
  /opt/mobile-detect.tar.gz
ADD https://github.com/YOURLS/dont-log-bots/archive/master.tar.gz             \
  /opt/dont-log-bots.tar.gz
ADD https://github.com/guessi/yourls-dont-log-health-checker/archive/master.tar.gz \
  /opt/dont-log-health-checker.tar.gz
ADD https://github.com/halkeye/YOURLS-OIDC/archive/refs/heads/patch-1.tar.gz \
  /opt/oidc.tar.gz
ADD https://github.com/halkeye/yourls-auditlogdb/archive/9ffcf72a6e4bc66232a930156e533a846e061211.tar.gz \
  /opt/auditlogdb.tar.gz
ADD https://github.com/air66design/air66-yourls-admin-theme/archive/master.tar.gz \
  /opt/air66-yourls-admin-theme.tar.gz
ADD --chmod=0755 https://raw.githubusercontent.com/joshp23/YOURLS-AuthMgrPlus/ff31aff5c2418277fd0c40bf87cb0ee44ef02249/authMgrPlus/plugin.php \
  user/plugins/authMgrPlus/plugin.php
ADD --chmod=0755 https://raw.githubusercontent.com/Diftraku/yourls_reverseproxy/refs/heads/master/reverseproxy/plugin.php \
  user/plugins/reverseproxy/plugin.php

RUN for i in $(ls /opt/*.tar.gz); do                                          \
  plugin_name="$(basename ${i} '.tar.gz')"                              ; \
  mkdir -p user/plugins/${plugin_name}                                  ; \
  tar zxvf /opt/${plugin_name}.tar.gz                                     \
  --strip-components=1                                                  \
  -C user/plugins/${plugin_name}                                      ; \
  done                                                                && \
  find user/plugins -name 'composer.lock' -execdir composer install \; ;

ADD conf/ /

# security enhancement: remove sample configs
RUN rm -rf user/config-sample.php                                             \
  user/plugins/sample*                                            && \
  (find . -type d -name ".git" -exec rm -rf {} +)

FROM yourls as noadmin

# security enhancement: leave only production required items
# ** note that it will still available somewhere in docker image layers
RUN rm -rf .git pages admin js css images sample* *.md                        \
  user/languages                                                     \
  user/plugins/random-bg                                             \
  yourls-api.php                                                     \
  yourls-infos.php                                                && \
  sed -i '/base64/d' yourls-loader.php                                   && \
  (find . -type f -name "*.html" ! -name "index.html" -delete)           && \
  (find . -type f -name "*.json" -o -name "*.md" -o -name "*.css" | xargs rm -f) && \
  (find . -type f -exec file {} + | awk -F: '{if ($2 ~/image/) print $1}' | xargs rm -f)

FROM yourls as theme

# please be aware that "Flynntes/Sleeky" here have no update for years
# you should take your own risk if you choose to have theme included
# - https://github.com/Flynntes/Sleeky/releases
# - https://github.com/Flynntes/Sleeky/issues

WORKDIR /opt/yourls

# sample configuration to integrate theme Sleeky-v2.5.0
# - ref: https://github.com/Flynntes/Sleeky#quick-start
ADD https://github.com/Flynntes/Sleeky/archive/refs/tags/v2.5.0.tar.gz        \
  /opt/theme-sleeky.tar.gz

RUN mkdir -p /tmp/sleeky-extracted                                         && \
  tar zxvf /opt/theme-sleeky.tar.gz                                         \
  --strip-components=1                                                  \
  -C /tmp/sleeky-extracted                                           && \
  mv -vf /tmp/sleeky-extracted/sleeky-backend user/plugins/theme-sleeky  && \
  mv -vf /tmp/sleeky-extracted/sleeky-frontend .                         && \
  rm -rvf /tmp/sleeky-extracted

ADD --chmod=755 https://raw.githubusercontent.com/YOURLS/containers/e914bdbc25dbb7c432dbffc858b3ba9b63b67321/images/yourls/config-container.php \
  /opt/yourls/user/config.php

RUN cat <<EOF >> /opt/yourls/user/config.php
define( 'OIDC_PROVIDER_URL', getenv_container('OIDC_PROVIDER_URL') );
define( 'OIDC_CLIENT_ID', getenv_container('OIDC_CLIENT_ID') );
define( 'OIDC_CLIENT_SECRET', getenv_container('OIDC_CLIENT_SECRET') );
define( 'OIDC_BYPASS_YOURLS_AUTH', true );
define( 'OIDC_SCOPES', ['email', 'openid', 'profile'] );
define( 'OIDC_USERNAME_FIELD', 'preferred_username' );

\$amp_default_role = "Editor";
\$amp_role_assignment = array(
  'administrator' => array(
    'halkeye'
  ),
  'editor' => array(
  ),
  'contributor' => array(
  )
);

// since i'm generating random bytes for passwords that change every requests, no need to try to re-encrypt them
define( 'YOURLS_NO_HASH_PASSWORD', true );
foreach (explode(",", getenv_container('YOURLS_ALLOWED_OIDC_USERS')) as \$user) {
  \$yourls_user_passwords[\$user] = random_bytes(10);
}
EOF
