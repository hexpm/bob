#!/bin/bash

set -euox pipefail

elixir=$1
erlang=$2
erlang_major=$3
os=$4
os_version=$5

tag=${elixir}-erlang-${erlang}-${os}-${os_version}

docker login docker.io --username ${BOB_DOCKERHUB_USERNAME} --password ${BOB_DOCKERHUB_PASSWORD}

docker build -t hexpm/elixir:${tag} --build-arg ELIXIR=${elixir} --build-arg ERLANG_MAJOR=${erlang_major} --build-arg ERLANG=${erlang} --build-arg OS_VERSION=${os_version} -f ${SCRIPT_DIR}/docker/elixir-${os}.dockerfile ${SCRIPT_DIR}
docker push docker.io/hexpm/elixir:${tag}
