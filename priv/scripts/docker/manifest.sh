#!/bin/bash

set -euox pipefail

kind=$1
tag=$2
archs=(${@:3})

export DOCKER_CLI_EXPERIMENTAL=enabled

arch_images=""

for arch in "${archs[@]}"; do
  arch_images="${arch_images} hexpm/${kind}-${arch}:${tag}"
done

# These commands have a tendancy to intermittently fail

docker manifest create --amend hexpm/${kind}:${tag} ${arch_images} ||
  (sleep $((10 + $RANDOM % 20)) && docker manifest create --amend hexpm/${kind}:${tag} ${arch_images}) ||
  (sleep $((10 + $RANDOM % 20)) && docker manifest create --amend hexpm/${kind}:${tag} ${arch_images}) ||
  (sleep $((10 + $RANDOM % 20)) && docker manifest create --amend hexpm/${kind}:${tag} ${arch_images}) ||
  (sleep $((10 + $RANDOM % 20)) && docker manifest create --amend hexpm/${kind}:${tag} ${arch_images})

docker manifest push --purge hexpm/${kind}:${tag} ||
  (sleep $((10 + $RANDOM % 20)) && docker manifest push --purge hexpm/${kind}:${tag}) ||
  (sleep $((10 + $RANDOM % 20)) && docker manifest push --purge hexpm/${kind}:${tag}) ||
  (sleep $((10 + $RANDOM % 20)) && docker manifest push --purge hexpm/${kind}:${tag}) ||
  (sleep $((10 + $RANDOM % 20)) && docker manifest push --purge hexpm/${kind}:${tag})
