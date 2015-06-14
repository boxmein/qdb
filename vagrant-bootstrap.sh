#!/bin/bash
# Install programs necessary to run this code

sudo apt-get update

echo "Installing Ruby and Postgres..."
sudo apt-get -y install ruby ruby-dev build-essential postgresql libpq-dev

echo "Installing gems..."
sudo gem install bundler
bundle install

echo "Copying over environment variables..."
echo "If you forgot to set environment variables, edit /vagrant/.env later."
# cp /vagrant/environment_variables ~/.bash_profile
cp /vagrant/environment_variables .env

echo "Installing Heroku toolchain..."

wget -qO- https://toolbelt.heroku.com/install-ubuntu.sh | sudo sh

echo "Done! \`cd /vagrant\` and run \`foreman start web\` to run the app. "
