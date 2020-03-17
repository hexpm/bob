ARG OS_VERSION
ARG ERLANG

FROM hexpm/erlang:${ERLANG}-debian-${OS_VERSION} AS build

RUN apt-get update
RUN apt-get -y --no-install-recommends install \
  wget \
  ca-certificates \
  tar \
  make \
  openssl

ARG ELIXIR

RUN wget -nv "https://github.com/elixir-lang/elixir/archive/v${ELIXIR}.tar.gz"
RUN mkdir /ELIXIR
RUN tar -zxf "v${ELIXIR}.tar.gz" -C /ELIXIR --strip-components=1
WORKDIR /ELIXIR
RUN make install

FROM debian:${OS_VERSION} AS final

RUN apt-get update && \
  apt-get -y --no-install-recommends install \
    libodbc1 \
    $(bash -c 'if [ "${ERLANG:0:1}" = "1" ]; then echo "libssl1.0.2"; else echo "libssl1.1"; fi') \
    libsctp1

COPY --from=build /usr/local /usr/local
ENV LANG=C.UTF-8
