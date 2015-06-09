#!/bin/bash
# Install programs necessary to run this code

sudo apt-get update

echo "Installing Ruby and Postgres..."
sudo apt-get -y install ruby ruby-dev postgresql libpq-dev

echo "Installing gems..."
sudo gem install bundler
bundle install

echo "Done!"
