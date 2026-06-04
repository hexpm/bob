#!/bin/bash

set -euox pipefail

kind=$1
tag=$2
archs=(${@:3})

arch_images=""

for arch in "${archs[@]}"; do
  arch_images="${arch_images} hexpm/${kind}-${arch}:${tag}"
done

# These commands have a tendancy to intermittently fail

docker buildx imagetools create -t hexpm/${kind}:${tag} ${arch_images} ||
  (sleep $((10 + $RANDOM % 20)) && docker buildx imagetools create -t hexpm/${kind}:${tag} ${arch_images}) ||
  (sleep $((10 + $RANDOM % 20)) && docker buildx imagetools create -t hexpm/${kind}:${tag} ${arch_images}) ||
  (sleep $((10 + $RANDOM % 20)) && docker buildx imagetools create -t hexpm/${kind}:${tag} ${arch_images}) ||
  (sleep $((10 + $RANDOM % 20)) && docker buildx imagetools create -t hexpm/${kind}:${tag} ${arch_images}) ||
  (exit 1)
