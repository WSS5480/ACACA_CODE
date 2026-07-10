#!/usr/bin/env bash
# Configure Bundler for deployment (Bundler 4.0+ compatibility)
# This script should be run before bundle install to avoid --deployment flag issues

set -e

echo "-----> Configuring Bundler for deployment mode (Bundler 4.0+)"
bundle config set --local deployment true
bundle config set --local path vendor/bundle
bundle config set --local without 'development test'

echo "-----> Bundler configured successfully"
