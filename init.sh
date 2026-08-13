#!/bin/bash

rm -rf composer.phar
wget https://github.com/composer/composer/releases/latest/download/composer.phar -O composer.phar
php composer.phar install -vvv
git submodule update --init --recursive --force
php artisan xboard:install

if [ -f "/etc/init.d/bt" ]; then
  chown -R www:www $(pwd);
fi