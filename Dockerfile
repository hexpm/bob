FROM hexpm/elixir:1.14.0-erlang-25.1-alpine-3.16.2 as build

# install build dependencies
RUN apk add --no-cache git

# prepare build dir
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
FROM alpine:3.16.2 AS app
RUN apk add --no-cache bash build-base coreutils curl docker gzip libffi-dev openssl openssl-dev pigz python3-dev py3-pip rust tar tarsnap wget zip

RUN pip install --no-cache-dir --upgrade awscli gsutil

COPY etc/tarsnap.conf /etc/tarsnap/tarsnap.conf
COPY etc/boto /app/.boto

WORKDIR /app

COPY --from=build /app/_build/prod/rel/bob ./

ENV HOME=/app
