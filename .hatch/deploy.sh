#!/usr/bin/env bash
# Custom deploy script that handles Bundler 4.0+ compatibility
# This replaces the default deploy script to avoid --deployment flag issues

set -e

echo "-----> Configuring Bundler for deployment mode (Bundler 4.0+)"
bundle config set --local deployment true
bundle config set --local path vendor/bundle
bundle config set --local without 'development test'

echo "-----> Installing gems..."
bundle install

echo "-----> Gems installed successfully"
