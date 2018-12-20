#!/bin/bash

# $1 = event
# $2 = ref

set -euox pipefail

source ${SCRIPT_DIR}/utils.sh

function push {
  image="gcr.io/hexpm-prod/bob-elixir-guides"
  container="elixir-guides"

  docker pull ${image} || true
  docker build -t ${image} -f ${SCRIPT_DIR}/elixir-guides.dockerfile ${SCRIPT_DIR}
  docker push ${image}
  docker rm ${container} || true
  docker run -t --name=${container} ${image}

  docker cp ${container}:/home/build/epub epub

  pushd epub
  for file in *.epub
  do
    echo $file
    aws s3 cp "${file}" "s3://s3.hex.pm/guides/elixir/${file}" --content-type "application/epub+zip" --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"guides","surrogate-control":"public,max-age=604800"}'
  done
  popd

  fastly_purge $BOB_FASTLY_SERVICE_HEXPM guides
}

if [ "$1" == "push" ] && [ "$2" == "master" ]; then
  push
fi
