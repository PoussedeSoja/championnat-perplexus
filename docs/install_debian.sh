#!/bin/bash

# ------------------------------------------------------------------------------------------------------
# !! 9/02/2019 -> this script need to be udpated and tested. For dev environement, use docker instead !!
# ------------------------------------------------------------------------------------------------------

# Launch as root or as sudoer user with `sudo ` before this script

# Settings you will have to adapt to your environment
WEB_DIR=/var/www/gogocarto # Where the source code will be installed
WEB_USR=www-data # Linux user for this app (if something else then www-data, you may have to change php-fpm default user)
WEB_GRP=www-data # Linux user group for this app (if something else then www-data, you may have to change php-fpm default user)
SSL_GENERATOR=selfsigned # SSL generator : certbot for production or on real internet dev, selfsigned for local dev
GIT_REPO=https://gitlab.adullact.net/pixelhumain/GoGoCarto.git # git repository for GoGoCarto
GIT_BRANCH=master # git branch for GoGoCarto
WEB_URL=gogocarto.local # main url for GoGoCarto
CONTACT_EMAIL=contact@gogocarto.local # default email contact
USE_AS_SAAS=false # true = allow to create a farm of map, false = single map
SECRET=`head -c 32 /dev/random | base64` # randomly generated string
MAILER_TRANSPORT=smtp # email transport protocol
MAILER_HOST=127.0.0.1 # email server host
MAILER_USER=null # email sender user
MAILER_PASSWORD=null # email sender password
CSRF_PROTECTION=true # CSRF protection for forms
OAUTH_COMMUNS_ID=disabled # oauth id for https://login.lescommuns.org
OAUTH_COMMUNS_SECRET=disabled # oauth secret for https://login.lescommuns.org
OAUTH_GOOGLE_ID=disabled # oauth id for google
OAUTH_GOOGLE_SECRET=disabled # oauth secret for google
OAUTH_FACEBOOK_ID=disabled # oauth id for facebook
OAUTH_FACEBOOK_SECRET=disabled # oauth secret for facebook


# Create user,folders and set permissions
id -u $WEB_USR &>/dev/null || useradd -g $WEB_GRP $WEB_USR
WEB_USR_HOME=`grep ${WEB_USR} /etc/passwd | cut -d ":" -f6`
mkdir -p $WEB_USR_HOME/.config $WEB_USR_HOME/.npm $WEB_USR_HOME/.composer $WEB_DIR
chown -R $WEB_USR:$(id -gn $WEB_USR) $WEB_USR_HOME/.config $WEB_USR_HOME/.npm $WEB_USR_HOME/.composer $WEB_DIR

# Install all usefull debian packages
apt update -y ;
apt dist-upgrade -y ;
apt install -y \
sudo \
curl \
build-essential \
git \
zip \
unzip \
php7.3-fpm \
php7.3 \
php7.3-cli \
php7.3-curl \
php7.3-dev \
php7.3-gd \
php7.3-bcmath \
php-mongodb \
php7.3-mbstring \
php7.3-zip \
nginx \
git-core \
mongodb \
openssl \
libsasl2-dev \
libssl-dev \
ssl-cert;
apt-get autoclean -y;

if [${SSL_GENERATOR} = 'certbot']
then
  sh -c 'echo "deb http://ftp.debian.org/debian stretch-backports main" > /etc/apt/sources.list.d/backports.list';
  apt-get update;
  apt-get install python-certbot-nginx -t stretch-backports; #cerbot needs to have recent version to handle wildcards
  if [${USE_AS_SAAS} = true]
  then
    # generate wildcard certificate with certbot (ATTENTION!!!! NEEDS MANUAL DNS CHALLENGE)
    certbot certonly \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --manual --preferred-challenges dns \
    --email ${CONTACT_EMAIL} --agree-tos \
    -d *.${WEB_URL} -d ${WEB_URL};
  else
    # generate classic ssl certificate with certbot
    certbot certonly --rsa-key-size 4096 --webroot -w /var/www/certbot/ --email ${CONTACT_EMAIL} --agree-tos -d ${WEB_URL};
  fi
  CERT_PATH=/etc/letsencrypt/live/${WEB_URL};
else
  CERT_PATH=${WEB_DIR};
  cd ${WEB_DIR};
  openssl req -x509 -out fullchain.pem -keyout privkey.pem \
  -newkey rsa:2048 -nodes -sha256 \
  -subj '/CN=localhost' -extensions EXT -config <( \
   printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth");
fi

# Install COMPOSER
cd /usr/src
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

# Install NODEJS
curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
sudo apt-get install -y --no-install-recommends nodejs
curl -L https://npmjs.org/install.sh | sudo sh

# Php extension ?
pecl install mongodb
pecl install imagick

# Pull GoGoCarto Source code
sudo -u $WEB_USR git clone -b $GIT_BRANCH $GIT_REPO $WEB_DIR
cd $WEB_DIR

# Set permissions in source directory
mkdir -p $WEB_DIR/web/uploads
chmod 777 -R $WEB_DIR/web/uploads $WEB_DIR/var

# npm stuff
npm install gulp -g
sudo -u $WEB_USR npm install

# TODO: create ENV file instead
sudo -u $WEB_USR echo "
APP_ENV=prod
APP_SECRET=${SECRET}
CSRF_PROTECTION=${CSRF_PROTECTION}
USE_AS_SAAS=${USE_AS_SAAS}
BASE_URL=${WEB_URL}

CONTACT_EMAIL=${CONTACT_EMAIL}
MAILER_URL=${MAILER_TRANSPORT}://${MAILER_USER}:${MAILER_PASSWORD}@${MAILER_HOST}

OAUTH_COMMUNS_ID=${OAUTH_COMMUNS_ID}
OAUTH_COMMUNS_SECRET=${OAUTH_COMMUNS_SECRET}
OAUTH_GOOGLE_ID=${OAUTH_GOOGLE_ID}
OAUTH_GOOGLE_SECRET=${OAUTH_GOOGLE_SECRET}
OAUTH_FACEBOOK_ID=${OAUTH_FACEBOOK_ID}
OAUTH_FACEBOOK_SECRET=${OAUTH_FACEBOOK_SECRET}
" > .env.local

sudo -u $WEB_USR php -d memory_limit=1024M /usr/local/bin/composer install;

sudo -u $WEB_USR php -d memory_limit=512M bin/console assets:install --symlink web  --no-interaction;

sudo -u $WEB_USR gulp build ;
sudo -u $WEB_USR gulp production ;

sudo -u $WEB_USR php -d memory_limit=512M $WEB_DIR/bin/console doctrine:mongodb:schema:create  --no-interaction;
sudo -u $WEB_USR php -d memory_limit=512M $WEB_DIR/bin/console doctrine:mongodb:generate:hydrators  --no-interaction;
sudo -u $WEB_USR php -d memory_limit=512M $WEB_DIR/bin/console doctrine:mongodb:generate:proxies  --no-interaction;
sudo -u $WEB_USR php -d memory_limit=512M $WEB_DIR/bin/console doctrine:mongodb:fixtures:load  --no-interaction;


echo "server {
  listen 80;
  listen [::]:80;
  server_name ${WEB_URL};

  access_log /var/log/nginx/${WEB_URL}.access.log;
  error_log /var/log/nginx/${WEB_URL}.error.log;

  location /.well-known/acme-challenge/ {
    default_type \"text/plain\";
    root /var/www/certbot;
  }

  location / { return 301 https://www.\$host\$request_uri; }
}

server {
  listen 80;
  listen [::]:80;
  server_name *.${WEB_URL};

  access_log /var/log/nginx/${WEB_URL}.access.log;
  error_log /var/log/nginx/${WEB_URL}.error.log;

  location /.well-known/acme-challenge/ {
    default_type \"text/plain\";
    root /var/www/certbot;
  }

  location / { return 301 https://\$host\$request_uri; }
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name *.${WEB_URL};

  root ${WEB_DIR}/web;

  # For example with certbot (you need a certificate to run https)
  ssl_certificate      ${CERT_PATH}/fullchain.pem;
  ssl_certificate_key  ${CERT_PATH}/privkey.pem;

  # Security hardening (as of 11/02/2018)
  ssl_protocols TLSv1.2; # TLSv1.3, TLSv1.2 if nginx >= 1.13.0
  ssl_prefer_server_ciphers on;
  ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256';
  # ssl_ecdh_curve secp384r1; # Requires nginx >= 1.1.0, not compatible with import-videos script
  ssl_session_timeout  10m;
  ssl_session_cache shared:SSL:10m;
  ssl_session_tickets off; # Requires nginx >= 1.5.9
  ssl_stapling on; # Requires nginx >= 1.3.7
  ssl_stapling_verify on; # Requires nginx => 1.3.7

  # Configure with your resolvers
  # resolver \$DNS-IP-1 \$DNS-IP-2 valid=300s;
  # resolver_timeout 5s;

  # Enable compression for JS/CSS/HTML bundle, for improved client load times.
  # It might be nice to compress JSON, but leaving that out to protect against potential
  # compression+encryption information leak attacks like BREACH.
  gzip on;
  gzip_types text/css text/html application/javascript;
  gzip_vary on;

  add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\";

  access_log /var/log/nginx/${WEB_URL}.access.log;
  error_log /var/log/nginx/${WEB_URL}.error.log;

  location ^~ '/.well-known/acme-challenge' {
    default_type \"text/plain\";
    root /var/www/certbot;
  }

    # cache.appcache, your document html and data
    location ~* \.(?:manifest|appcache|html?|xml|json)$ {
    add_header Cache-Control \"max-age=0\";
    }

    # Feed
    location ~* \.(?:rss|atom)$ {
    add_header Cache-Control \"max-age=3600\";
    }

    # Media: images, icons, video, audio, HTC
    location ~* \.(?:jpg|jpeg|gif|png|ico|cur|gz|svg|mp4|ogg|ogv|webm|htc|lang)$ {
    access_log off;
    add_header Cache-Control \"max-age=2592000\";
    }

    # Uploads
    location /uploads/ {
    access_log off;
    add_header Cache-Control \"max-age=2592000\";
    }

    # Media: svgz files are already compressed.
    location ~* \.svgz$ {
    access_log off;
    gzip off;
    add_header Cache-Control \"max-age=2592000\";
    }

    # CSS and Javascript
    location ~* \.(?:css|js)$ {
    add_header Cache-Control \"max-age=31536000\";
    access_log off;
    }

    # WebFonts
  location ~* \.(?:ttf|ttc|otf|eot|woff|woff2)$ {
    add_header Cache-Control \"max-age=2592000\";
    access_log off;
  }

  # strip index.php/ prefix if it is present
  rewrite ^/index\.php/?(.*)$ /\$1 permanent;

  location / {
    index index.php;
    try_files \$uri @rewriteapp;
  }

  location @rewriteapp {
    rewrite ^(.*)$ /index.php/\$1 last;
  }

  # pass the PHP scripts to FastCGI server from upstream phpfcgi
  location ~ ^/(index|config)\.php(/|$) {
    fastcgi_pass unix:/var/run/php/php7.3-fpm.sock;
    fastcgi_split_path_info ^(.+\.php)(/.*)$;
    include fastcgi_params;
    fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_param  HTTPS off;
  }
}" > /etc/nginx/sites-available/${WEB_URL}
ln -nsf /etc/nginx/sites-available/${WEB_URL} /etc/nginx/sites-enabled/${WEB_URL}
nginx -t && service nginx restart

# TODO add crontab automatically