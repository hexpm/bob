#!/bin/bash

set -euox pipefail

erlang=$1
alpine=$2

tag=${erlang}-alpine-${alpine}

docker login docker.io --username ${BOB_DOCKERHUB_USERNAME} --password ${BOB_DOCKERHUB_PASSWORD}

docker build -t hexpm/erlang:${tag} --build-arg ERLANG=${erlang} --build-arg ALPINE=${alpine} -f ${SCRIPT_DIR}/docker/erlang.dockerfile ${SCRIPT_DIR}
docker push docker.io/hexpm/erlang:${tag}
