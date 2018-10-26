#!/bin/bash

# $1 = event
# $2 = ref
# $@ = otp_versions

set -e -u

APPS=(eex elixir ex_unit iex logger mix)

source ${SCRIPT_DIR}/utils.sh

# $1 = ref
# $@ = otp_versions
function push {
  original_path=${PATH}
  otp_versions=(${@:2})

  otp_version=${otp_versions[0]}
  otp_string=$(otp_string ${otp_version})
  build "$1" "${otp_version}" "1"
  upload_build "$1" ""
  upload_build "$1" "${otp_string}"
  upload_docs "$1"

  for otp_version in "${otp_versions[@]:1}"; do
    otp_string=$(otp_string ${otp_version})
    build "$1" "${otp_version}" "0"
    upload_build "$1" "${otp_string}"
  done

  PATH=${original_path}
}

# $1 = version
function otp_string {
  otp_string=$(echo "$1" | awk 'match($0, /^[0-9][0-9]/) { print substr( $0, RSTART, RLENGTH )}')
  otp_string="-otp-${otp_string}"
  echo "${otp_string}"
}

# $1 = ref
# $2 = otp_version
# $3 = build_docs
function build {
  echo "Building Elixir $1 with OTP $2 BUILD_DOCS=$3"
  ref=$(echo ${1} | sed -e 's/\//-/g')
  container="bob-elixir-otp-${2}-ref-${ref}"
  image="gcr.io/hexpm-prod/bob-elixir"
  tag="otp-${2}"

  docker pull ${image}:${tag} || true
  docker build --build-arg otp_version=${2} -t ${image}:${tag} -f ${SCRIPT_DIR}/elixir.dockerfile ${SCRIPT_DIR}
  docker push ${image}:${tag}
  docker rm ${container} || true
  docker run -t -e ELIXIR_REF=${1} -e BUILD_DOCS=${3} --name=${container} ${image}:${tag}

  docker cp ${container}:/home/build/elixir.zip elixir.zip
  docker cp ${container}:/home/build/versioned-docs versioned-docs || true
  docker cp ${container}:/home/build/unversioned-docs unversioned-docs || true
}

# $1 = ref
# $2 = otp
function upload_build {
  aws s3 cp elixir.zip "s3://s3.hex.pm/builds/elixir/${1}${2}.zip" --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"builds","surrogate-control":"public,max-age=604800"}'
  fastly_purge $BOB_FASTLY_SERVICE_HEXPM builds
}

# $1 = ref
function upload_docs {
  version=$(echo "${1}" | sed 's/^v//g')

  pushd versioned-docs
  for app in "${APPS[@]}"; do
    aws s3 cp "${app}" "s3://hexdocs.pm/${app}/${version}" --recursive --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docspage/${app}/${version}\",\"surrogate-control\":\"public,max-age=604800\"}"
    fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}/${version}"

    tar -czf "${app}-${version}.tar.gz" -C "${app}" .
    aws s3 cp "${app}-${version}.tar.gz" "s3://s3.hex.pm/docs/${app}-${version}.tar.gz" --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docs/${app}-${version}\",\"surrogate-control\":\"public,max-age=604800\"}"
    fastly_purge $BOB_FASTLY_SERVICE_HEXPM "docs/${app}-${version}"
  done
  popd

  if [ -f unversioned-docs ]; then
    pushd unversioned-docs
    for app in "${APPS[@]}"; do
      aws s3 cp "${app}" "s3://hexdocs.pm/${app}" --recursive --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docspage/${app}\",\"surrogate-control\":\"public,max-age=604800\"}"
      fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}"
    done
    popd
  fi
}

# $1 = ref
function delete {
  aws s3 rm "s3://s3.hex.pm/builds/elixir/${1}.zip"
  aws s3 rm "s3://s3.hex.pm" --recursive --exclude "*" --include "builds/elixir/${1}-otp-*.zip"

  for app in "${APPS[@]}"; do
    version=$(echo "${1}" | sed 's/^v//g')

    aws s3 rm "s3://s3.hex.pm/docs/${app}-${version}.tar.gz"
    fastly_purge $BOB_FASTLY_SERVICE_HEXPM builds

    aws s3 rm "s3://hexdocs.pm/${app}/${version}" --recursive
    fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}/${version}"
  done
}

case "$1" in
  "push" | "create")
    echo "Building $2 ${@:3}"
    push "$2" ${@:3}
    ;;
  "delete")
    delete "$2"
    ;;
esac
