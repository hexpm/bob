#!/bin/bash

set -euox pipefail

erlang=$1
os=$2
os_version=$3
arch=$4

tag=${erlang}-${os}-${os_version}

case "${os}" in
  "alpine")
    dockerfile="erlang-alpine.dockerfile"
    ;;
  "ubuntu")
    split_os_version=(${os_version//-/ })
    dockerfile="erlang-ubuntu-${split_os_version[0]}.dockerfile"
    ;;
  "debian")
    split_os_version=(${os_version//-/ })
    dockerfile="erlang-debian-${split_os_version[0]}.dockerfile"
    ;;
esac

# Disable PIE for OTP prior to 21; see http://erlang.org/doc/apps/hipe/notes.html#hipe-3.18
pie_cflags="-fpie"
pie_ldflags="-pie"
if [ "$(echo ${erlang} | cut -d '.' -f 1)" -le "20" ]; then
  pie_cflags=""
  pie_ldflags=""
fi

docker build \
  -t hexpm/erlang-${arch}:${tag} \
  --build-arg ERLANG=${erlang} \
  --build-arg OS_VERSION=${os_version} \
  --build-arg PIE_CFLAGS=${pie_cflags} \
  --build-arg PIE_LDFLAGS=${pie_ldflags} \
  -f ${SCRIPT_DIR}/docker/${dockerfile} ${SCRIPT_DIR}/docker

# Smoke test
docker run --rm hexpm/erlang-${arch}:${tag} erl -s erlang halt

# This command have a tendancy to intermittently fail
docker push docker.io/hexpm/erlang-${arch}:${tag} ||
  (sleep $((20 + $RANDOM % 40)) && docker push docker.io/hexpm/erlang-${arch}:${tag}) ||
  (sleep $((20 + $RANDOM % 40)) && docker push docker.io/hexpm/erlang-${arch}:${tag}) ||
  (sleep $((20 + $RANDOM % 40)) && docker push docker.io/hexpm/erlang-${arch}:${tag}) ||
  (sleep $((20 + $RANDOM % 40)) && docker push docker.io/hexpm/erlang-${arch}:${tag}) ||
  (exit 0)

docker rmi -f docker.io/hexpm/erlang-${arch}:${tag}
