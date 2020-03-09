ARG OS_VERSION
ARG ERLANG

FROM hexpm/erlang:${ERLANG}-alpine-${OS_VERSION} AS build

RUN apk add --no-cache --update \
  wget \
  tar \
  make

ARG ELIXIR

RUN wget -nv "https://github.com/elixir-lang/elixir/archive/v${ELIXIR}.tar.gz"
RUN mkdir /ELIXIR
RUN tar -zxf "v${ELIXIR}.tar.gz" -C /ELIXIR --strip-components=1
WORKDIR /ELIXIR
RUN make install

FROM alpine:${OS_VERSION} AS final

RUN apk add --update --no-cache \
  ncurses \
  $(if [ "${ERLANG:0:1}" = "1" ]; then echo "libressl"; else echo "openssl"; fi) \
  unixodbc \
  lksctp-tools

COPY --from=build /usr/local /usr/local
