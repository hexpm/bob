#!/bin/bash

set -euox pipefail

elixir=$1
erlang=$2
os=$3
os_version=$4

tag=${elixir}-erlang-${erlang}-${os}-${os_version}

docker login docker.io --username ${BOB_DOCKERHUB_USERNAME} --password ${BOB_DOCKERHUB_PASSWORD}

case "${os}" in
  "alpine")
    dockerfile="elixir-alpine.dockerfile"
    ;;
  "ubuntu")
    split_os_version=(${os_version//-/ })
    dockerfile="elixir-ubuntu-${split_os_version[0]}.dockerfile"
    ;;
esac

docker build -t hexpm/elixir:${tag} --build-arg ELIXIR=${elixir} --build-arg ERLANG=${erlang} --build-arg OS_VERSION=${os_version} -f ${SCRIPT_DIR}/docker/${dockerfile} ${SCRIPT_DIR}/docker
docker push docker.io/hexpm/elixir:${tag}
docker rmi -f docker.io/hexpm/elixir:${tag}
