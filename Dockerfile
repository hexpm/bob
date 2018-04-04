FROM alpine:3.7 AS builder

RUN mkdir /build
WORKDIR /build

ENV MIX_ENV=prod
ENV APP_NAME=bob
ENV APP_ERLANG_VERSION=20.3
ENV APP_ELIXIR_VERSION=1.6.4

RUN apk --no-cache upgrade

RUN apk add --update \
  git \
  wget \
  curl \
  unzip \
  bash \
  openssl

RUN git clone https://github.com/asdf-vm/asdf.git /asdf --branch v0.4.3
ENV PATH="$PATH:/asdf/shims:/asdf/bin"
RUN asdf plugin-add erlang
RUN asdf plugin-add elixir
COPY build/asdf-install-otp.sh asdf-install-otp.sh

RUN ./asdf-install-otp.sh $APP_ERLANG_VERSION alpine-3.7
RUN asdf install elixir $APP_ELIXIR_VERSION

RUN asdf global erlang $APP_ERLANG_VERSION
RUN asdf global elixir $APP_ELIXIR_VERSION

COPY mix.exs mix.lock /build/
COPY config /build/config
COPY priv /build/priv

RUN \
  mix local.hex --force && \
  mix local.rebar --force && \
  mix deps.get && \
  mix deps.compile

COPY lib /build/lib
COPY rel/config.exs /build/rel/config.exs

RUN \
  mix compile && \
  mix release --env=$MIX_ENV

RUN mv _build/$MIX_ENV/rel/$APP_NAME/releases/*/$APP_NAME.tar.gz .



FROM alpine:3.7 as app

ENV APP_NAME=bob

RUN apk --no-cache upgrade

RUN apk add --update \
  py2-pip \
  tarsnap \
  git \
  wget \
  curl \
  unzip \
  bash \
  openssl

RUN pip install awscli --upgrade --user

RUN git clone https://github.com/asdf-vm/asdf.git /asdf --branch v0.4.3
ENV PATH="$PATH:/asdf/shims:/asdf/bin"
COPY build/asdf-install-otp.sh asdf-install-otp.sh
RUN asdf plugin-add erlang
RUN asdf plugin-add elixir

# RUN ./asdf-install-otp.sh 17.3 alpine-3.7
# RUN ./asdf-install-otp.sh 17.5 alpine-3.7
# RUN ./asdf-install-otp.sh 18.3 alpine-3.7
# RUN ./asdf-install-otp.sh 19.3 alpine-3.7
# RUN ./asdf-install-otp.sh 20.2 alpine-3.7
RUN ./asdf-install-otp.sh 20.3 alpine-3.7

COPY --from=builder /build/$APP_NAME.tar.gz ./
RUN mkdir /app && tar xf $APP_NAME.tar.gz -C /app && rm $APP_NAME.tar.gz
WORKDIR /app

# Hardocded app name :(
ENTRYPOINT ["bin/bob", "foreground"]




# RUN apt install -y docker docker.io
# sudo groupadd docker
# sudo usermod -aG docker $USER
