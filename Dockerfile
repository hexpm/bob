ARG ELIXIR_VERSION=1.18.1
ARG ERLANG_VERSION=27.2
ARG DEBIAN_VERSION=bookworm-20241223-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-debian-${DEBIAN_VERSION} AS build

ENV LANG=C.UTF-8

# install build dependencies
RUN apt update -y && \
    apt upgrade -y && \
    apt install -y --no-install-recommends git build-essential ca-certificates gnupg lsb-release wget && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

RUN wget https://pkg.tarsnap.com/tarsnap-deb-packaging-key.asc && \
    gpg --dearmor tarsnap-deb-packaging-key.asc && \
    mv tarsnap-deb-packaging-key.asc.gpg tarsnap-archive-keyring.gpg && \
    cp tarsnap-archive-keyring.gpg /usr/share/keyrings/ && \
    echo "deb [signed-by=/usr/share/keyrings/tarsnap-archive-keyring.gpg] http://pkg.tarsnap.com/deb/$(lsb_release -s -c) ./" | tee -a /etc/apt/sources.list.d/tarsnap.list

RUN apt update -y && \
    apt install --no-install-recommends -y tarsnap-archive-keyring && \
    echo "deb-src [signed-by=/usr/share/keyrings/tarsnap-archive-keyring.gpg] http://pkg.tarsnap.com/deb-src ./" | tee -a /etc/apt/sources.list.d/tarsnap.list && \
    apt update -y && \
    gpg --no-default-keyring --keyring trustedkeys.gpg --import /usr/share/keyrings/tarsnap-archive-keyring.gpg && \
    apt build-dep -y tarsnap && \
    apt source -b tarsnap && \
    dpkg -i tarsnap_*.deb

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
RUN mix compile

# build release
COPY rel rel
RUN mix do sentry.package_source_code, release

# prepare release image
FROM debian:${DEBIAN_VERSION} AS app

RUN apt update -y && \
    apt install --no-install-recommends -y apt-transport-https awscli bash build-essential ca-certificates coreutils curl docker.io gnupg gzip libffi-dev libssl-dev openssl pigz python3-dev tar zip

RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    apt update -y && apt install --no-install-recommends -y google-cloud-cli

COPY --from=build /usr/bin/tarsnap* /usr/bin/

COPY etc/tarsnap.conf /etc/tarsnap/tarsnap.conf
COPY etc/boto /app/.boto

WORKDIR /app

COPY --from=build /app/_build/prod/rel/bob ./
RUN mkdir /boto /tarsnap
RUN chown -R nobody: /app /boto /tarsnap
USER nobody

ENV HOME=/app
ENV LANG=C.UTF-8
