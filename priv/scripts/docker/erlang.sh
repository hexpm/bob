#!/bin/bash

set -euox pipefail

erlang=$1
os=$2
os_version=$3

tag=${erlang}-${os}-${os_version}

docker login docker.io --username ${BOB_DOCKERHUB_USERNAME} --password ${BOB_DOCKERHUB_PASSWORD}

docker build -t hexpm/erlang:${tag} --build-arg ERLANG=${erlang} --build-arg OS_VERSION=${os_version} -f ${SCRIPT_DIR}/docker/erlang-${os}.dockerfile ${SCRIPT_DIR}
docker push docker.io/hexpm/erlang:${tag}
