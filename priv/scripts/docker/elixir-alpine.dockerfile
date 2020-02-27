ARG OS_VERSION
ARG ERLANG

FROM alpine:${OS_VERSION} AS build

ARG ERLANG_MAJOR
ARG ELIXIR

RUN apk add --no-cache --update wget zip
RUN wget -q -O /tmp/elixir.zip https://repo.hex.pm/builds/elixir/v${ELIXIR}-otp-${ERLANG_MAJOR}.zip
RUN unzip -d /elixir /tmp/elixir.zip

FROM hexpm/erlang:${ERLANG}-alpine-${OS_VERSION} AS final

RUN mkdir /elixir
COPY --from=build /elixir /elixir
ENV PATH=/elixir/bin:$PATH
