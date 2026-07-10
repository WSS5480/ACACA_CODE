#!/usr/bin/env bash
# Pre-deploy script for Hatchbox deployments
# This script runs before the deploy script and configures Bundler 4.0+ compatibility

set -e

echo "-----> Configuring Bundler for deployment mode (Bundler 4.0+)"
bundle config set --local deployment true
bundle config set --local path vendor/bundle
bundle config set --local without 'development test'

echo "-----> Bundler configured successfully"
