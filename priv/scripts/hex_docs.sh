#!/bin/bash

# $1 = event
# $2 = ref

set -e -u

source ${SCRIPT_DIR}/utils.sh

# $1 = ref
function build {
  image="gcr.io/hexpm-prod/bob-hex-docs"
  container="hex-docs"

  docker pull ${image} || true
  docker build -t ${image} -f ${SCRIPT_DIR}/hex-docs.dockerfile ${SCRIPT_DIR}
  docker push ${image}
  docker rm ${container} || true
  docker run -t -e HEX_REF=${1} --name=${container} ${image}

  docker cp ${container}:/home/build/versioned-docs versioned-docs || true
  docker cp ${container}:/home/build/unversioned-docs unversioned-docs || true
}

# $1 = ref
function push {
  app=hex
  version=$(echo "${1}" | sed -e 's/^v//g' | sed -e 's/\//-/g')

  pushd versioned-docs
  aws s3 cp . "s3://hexdocs.pm/${app}/${version}" --recursive --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docspage/${app}/${version}\",\"surrogate-control\":\"public,max-age=604800\"}"
  fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}/${version}"

  tar -czf "${app}-${version}.tar.gz" -C "${app}" .
  aws s3 cp "${app}-${version}.tar.gz" "s3://s3.hex.pm/docs/${app}-${version}.tar.gz" --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docs/${app}-${version}\",\"surrogate-control\":\"public,max-age=604800\"}"
  fastly_purge $BOB_FASTLY_SERVICE_HEXPM "docs/${app}-${version}"
  popd

  if [ -f unversioned-docs ]; then
    pushd unversioned-docs
    aws s3 cp . "s3://hexdocs.pm/${app}" --recursive --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docspage/${app}\",\"surrogate-control\":\"public,max-age=604800\"}"
    fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}"
  fi
}

if [ "$1" == "push" ]; then
  build $2
  push $2
fi
