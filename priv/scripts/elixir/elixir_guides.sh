#!/bin/bash

set -euox pipefail

source ${SCRIPT_DIR}/utils.sh

ref=$1

function push {
  image="bob-elixir-guides"
  container="elixir-guides"

  docker build -t ${image} -f ${SCRIPT_DIR}/elixir/elixir-guides.dockerfile ${SCRIPT_DIR}
  docker rm ${container} || true
  docker run -t --name=${container} ${image}

  docker cp ${container}:/home/build/epub epub

  docker rm -f ${container}

  pushd epub
  for file in *.epub
  do
    echo ${file}
    aws s3 cp "${file}" "s3://s3.hex.pm/guides/elixir/${file}" --content-type "application/epub+zip" --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"guides","surrogate-control":"public,max-age=604800"}'
  done
  popd

  echo ${ref} > ref.txt
  aws s3 cp ref.txt "s3://s3.hex.pm/guides/elixir/ref.txt"

  fastly_purge $BOB_FASTLY_SERVICE_HEXPM guides
}

push
