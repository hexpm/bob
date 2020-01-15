#!/bin/bash

set -euox pipefail

elixir=$1
erlang=$2
erlang_major=$3
alpine=$4

tag=${elixir}-erlang-${erlang}-alpine-${alpine}

docker login docker.io --username ${DOCKERHUB_USERNAME} --password ${DOCKERHUB_PASSWORD}

docker build -t hexpm/elixir:${tag} --build-arg ELIXIR=${elixir} --build-arg ERLANG_MAJOR=${erlang_major} --build-arg ERLANG=${erlang} --build-arg ALPINE=${alpine} -f ${SCRIPT_DIR}/docker/elixir.dockerfile ${SCRIPT_DIR}
docker push docker.io/hexpm/elixir:${tag}
