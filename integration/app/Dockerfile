# Select base image
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

WORKDIR /app
COPY . .

# Set entrypoint
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["bundle exec rake test"]
