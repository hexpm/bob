#!/bin/bash

# $1 = ref

set -euox pipefail

source ${SCRIPT_DIR}/utils.sh

# $1 = ref
function build {
  image="bob-hex-docs"
  container="hex-docs"

  docker build -t ${image} -f ${SCRIPT_DIR}/hex/hex-docs.dockerfile ${SCRIPT_DIR}
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
  gsutil -m -h "cache-control: public,max-age=3600" -h "x-goog-meta-surrogate-key: docspage/${app}/${version}" -h "x-goog-meta-surrogate-control: public,max-age=604800" rsync -d -r . "gs://hexdocs.pm/${app}/${version}"
  fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}/${version}"

  gsutil -m -h "cache-control: public,max-age=3600" -h "x-goog-meta-surrogate-key: docspage/${app}/docs_config.js" -h "x-goog-meta-surrogate-control: public,max-age=604800" cp docs_config.js "gs://hexdocs.pm/${app}"
  fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}/docs_config.js"
  popd

  if [ -d unversioned-docs ]; then
    pushd unversioned-docs
    gsutil -m -h "cache-control: public,max-age=3600" -h "x-goog-meta-surrogate-key: docspage/${app}" -h "x-goog-meta-surrogate-control: public,max-age=604800" cp -r . "gs://hexdocs.pm/${app}"
    fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}"
  fi

  tar -czf "${app}-${version}.tar.gz" -C versioned-docs .
  aws s3 cp "${app}-${version}.tar.gz" "s3://s3.hex.pm/docs/${app}-${version}.tar.gz" --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docs/${app}-${version}\",\"surrogate-control\":\"public,max-age=604800\"}"
  fastly_purge $BOB_FASTLY_SERVICE_HEXPM "docs/${app}-${version}"
}

build $1
push $1
