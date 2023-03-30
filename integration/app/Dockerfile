# Select base image
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

WORKDIR /app
COPY . .
RUN bundle install

# Set entrypoint
ENTRYPOINT ["/bin/bash", "-c"]
CMD [ "pwd" ]
