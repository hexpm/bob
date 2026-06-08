ARG ELIXIR_VERSION=1.18.1
ARG ERLANG_VERSION=27.3.4.12
ARG DEBIAN_VERSION=bookworm-20260518-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-debian-${DEBIAN_VERSION} AS build

ENV LANG=C.UTF-8

# install build dependencies
RUN apt update -y && \
    apt upgrade -y && \
    apt install -y --no-install-recommends git build-essential ca-certificates && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

# prepare build dir
RUN mkdir /app
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get
RUN mix deps.compile

# build project
COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.deploy
RUN mix compile

# build release
COPY rel rel
RUN mix do sentry.package_source_code, release

# prepare release image
FROM debian:${DEBIAN_VERSION} AS app

RUN apt update -y && \
    apt install --no-install-recommends -y apt-transport-https awscli bash build-essential ca-certificates coreutils curl docker.io gnupg gzip libffi-dev libssl-dev openssl python3-dev tar zip

ARG BUILDX_VERSION=0.17.1
RUN mkdir -p /usr/libexec/docker/cli-plugins && \
    curl -fsSL "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-$(dpkg --print-architecture)" \
      -o /usr/libexec/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/libexec/docker/cli-plugins/docker-buildx

RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    apt update -y && apt install --no-install-recommends -y google-cloud-cli

COPY etc/boto /app/.boto

WORKDIR /app

COPY --from=build /app/_build/prod/rel/bob ./
RUN mkdir /boto /persist
RUN chown -R nobody: /app /boto /persist
USER nobody

ENV HOME=/app
ENV LANG=C.UTF-8
