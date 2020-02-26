ARG OS_VERSION
ARG ERLANG

FROM ubuntu:${OS_VERSION} AS build

ARG ERLANG_MAJOR
ARG ELIXIR

RUN apt-get update
RUN apt-get -y install wget unzip
RUN wget -q -O /tmp/elixir.zip https://repo.hex.pm/builds/elixir/v${ELIXIR}-otp-${ERLANG_MAJOR}.zip
RUN unzip -d /elixir /tmp/elixir.zip

FROM hexpm/erlang:${ERLANG}-ubuntu-${OS_VERSION} AS final

RUN mkdir /elixir
COPY --from=build /elixir /elixir
ENV PATH=/elixir/bin:$PATH LANG=C.UTF-8
