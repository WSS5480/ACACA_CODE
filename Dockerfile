# syntax = docker/dockerfile:1
ARG RUBY_VERSION=3.3.2
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base
WORKDIR /rails
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

FROM base as build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips pkg-config
COPY Gemfile Gemfile.lock ./
RUN bundle config set deployment true && \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile
COPY . .
RUN chmod +x bin/*
RUN bundle exec bootsnap precompile app/ lib/

FROM base
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libsqlite3-0 libvips && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER rails:rails
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server"]
