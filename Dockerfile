FROM ubuntu:16.04 AS builder

RUN mkdir /build
WORKDIR /build

ENV MIX_ENV=prod
ENV APP_NAME=bob
ENV APP_ERLANG_VERSION=20.3
ENV APP_ELIXIR_VERSION=1.6.4

RUN apt-get update
RUN apt-get install -y \
  git \
  wget \
  curl \
  unzip \
  locales

RUN git clone https://github.com/asdf-vm/asdf.git /asdf --branch v0.4.3
ENV PATH="$PATH:/asdf/shims:/asdf/bin"
COPY build/asdf-install-otp.sh asdf-install-otp.sh
RUN asdf plugin-add erlang
RUN asdf plugin-add elixir

RUN ./asdf-install-otp.sh $APP_ERLANG_VERSION
RUN asdf install elixir $APP_ELIXIR_VERSION

RUN asdf global erlang $APP_ERLANG_VERSION
RUN asdf global elixir $APP_ELIXIR_VERSION

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

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



FROM ubuntu:16.04 as app

ENV APP_NAME=bob

RUN echo "deb http://pkg.tarsnap.com/deb/xenial ./" > /etc/apt/sources.list.d/tarsnap.list

RUN apt-get update
RUN apt-get install -y --allow-unauthenticated \
  python-pip \
  tarsnap \
  git \
  wget \
  curl \
  unzip \
  locales \
  automake \
  autoconf \
  libreadline-dev \
  libncurses-dev \
  libssl-dev \
  libyaml-dev \
  libxslt-dev \
  libffi-dev \
  libtool \
  unixodbc-dev

RUN pip install awscli --upgrade --user

RUN git clone https://github.com/asdf-vm/asdf.git /asdf --branch v0.4.3
ENV PATH="$PATH:/asdf/shims:/asdf/bin"
COPY build/asdf-install-otp.sh asdf-install-otp.sh
RUN asdf plugin-add erlang
RUN asdf plugin-add elixir

RUN ./asdf-install-otp.sh 17.3
RUN ./asdf-install-otp.sh 17.5
RUN ./asdf-install-otp.sh 18.3
RUN ./asdf-install-otp.sh 19.3
RUN ./asdf-install-otp.sh 20.2
RUN ./asdf-install-otp.sh 20.3

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

COPY --from=builder /build/$APP_NAME.tar.gz ./
RUN mkdir /app && tar xf $APP_NAME.tar.gz -C /app && rm $APP_NAME.tar.gz
WORKDIR /app

ENTRYPOINT bin/$APP_NAME foreground




# RUN apt install -y docker docker.io
# sudo groupadd docker
# sudo usermod -aG docker $USER
