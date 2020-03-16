#!/bin/bash

set -euox pipefail

erlang=$1
os=$2
os_version=$3

tag=${erlang}-${os}-${os_version}

docker login docker.io --username ${BOB_DOCKERHUB_USERNAME} --password ${BOB_DOCKERHUB_PASSWORD}

case "${os}" in
  "alpine")
    dockerfile="erlang-alpine.dockerfile"
    ;;
  "ubuntu")
    split_os_version=(${os_version//-/ })
    dockerfile="erlang-ubuntu-${split_os_version[0]}.dockerfile"
    ;;
esac

docker build -t hexpm/erlang:${tag} --build-arg ERLANG=${erlang} --build-arg OS_VERSION=${os_version} -f ${SCRIPT_DIR}/docker/${dockerfile} ${SCRIPT_DIR}/docker
docker push docker.io/hexpm/erlang:${tag}
docker rmi -f docker.io/hexpm/erlang:${tag}
