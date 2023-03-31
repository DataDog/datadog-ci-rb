ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en

RUN mkdir -p "$GEM_HOME" && chmod -R 777 "$GEM_HOME"

# Upgrade RubyGems and Bundler
RUN gem update --system 3.3.26
RUN gem install bundler -v '~> 2.3.26'
ENV BUNDLE_SILENCE_ROOT_WARNING 1

RUN mkdir /app
WORKDIR /app
COPY . .

# Set entrypoint
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["bundle exec rake test"]
