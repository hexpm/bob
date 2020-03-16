#!/bin/bash

# $1 = ref
# $@ = otp_versions

set -euox pipefail

APPS=(eex elixir ex_unit iex logger mix)

source ${SCRIPT_DIR}/utils.sh

# $1 = ref
# $2 = sha
# $@ = otp_versions
function push {
  original_path=${PATH}
  otp_versions=(${@:3})

  otp_version=${otp_versions[0]}
  otp_string=$(otp_string ${otp_version})
  build "$1" "$2" "${otp_version}" "1"
  upload_build "$1" "${otp_string}"
  upload_docs "$1"
  update_builds_txt "$1" "$2" "${otp_string}"

  for otp_version in "${otp_versions[@]:1}"; do
    otp_string=$(otp_string ${otp_version})
    build "$1" "$2" "${otp_version}" "0"
    upload_build "$1" "${otp_string}"
    update_builds_txt "$1" "$2" "${otp_string}"
  done

  upload_build "$1" ""
  update_builds_txt "$1" "$2" ""

  fastly_purge $BOB_FASTLY_SERVICE_HEXPM builds

  PATH=${original_path}
}

# $1 = version
function otp_string {
  otp_string=$(echo "$1" | awk 'match($0, /^[0-9][0-9]/) { print substr( $0, RSTART, RLENGTH )}')
  otp_string="-otp-${otp_string}"
  echo "${otp_string}"
}

# $1 = ref
# $2 = sha
# $3 = otp_version
# $4 = build_docs
function build {
  echo "Building Elixir $1 $2 with OTP $3 BUILD_DOCS=$4"
  ref=$(echo ${1} | sed -e 's/\//-/g')
  container="bob-elixir-otp-${3}-ref-${ref}"
  image="bob-elixir"
  tag="otp-${3}"

  docker build --build-arg otp_version=${3} -t ${image}:${tag} -f ${SCRIPT_DIR}/elixir/elixir.dockerfile ${SCRIPT_DIR}
  docker rm -f ${container} || true
  docker run -t -e ELIXIR_REF=${1} -e ELIXIR_SHA=${2} -e BUILD_DOCS=${4} --name=${container} ${image}:${tag}

  docker cp ${container}:/home/build/elixir.zip elixir.zip
  docker cp ${container}:/home/build/versioned-docs versioned-docs || true
  docker cp ${container}:/home/build/unversioned-docs unversioned-docs || true

  docker rm -f ${container}
  docker rmi -f ${image}:${tag}
}

# $1 = ref
# $2 = otp
function upload_build {
  version=$(echo ${1} | sed -e 's/\//-/g')
  aws s3 cp elixir.zip "s3://s3.hex.pm/builds/elixir/${version}${2}.zip" --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"builds","surrogate-control":"public,max-age=604800"}'
}

# $1 = ref
# $2 = sha
# $3 = otp
function update_builds_txt {
  date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  build_sha256=$(sha256sum elixir.zip | cut -d ' ' -f 1)

  aws s3 cp s3://s3.hex.pm/builds/elixir/builds.txt builds.txt || true
  touch builds.txt

  sed -i "/^${1}${3} /d" builds.txt

  echo -e "${1}${3} ${2} ${date} ${build_sha256} \n$(cat builds.txt)" > builds.txt

  sort -u -k1,1 -o builds.txt builds.txt
  aws s3 cp builds.txt s3://s3.hex.pm/builds/elixir/builds.txt --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"builds","surrogate-control":"public,max-age=604800"}'
}

# $1 = ref
function upload_docs {
  version=$(echo "${1}" | sed -e 's/^v//g' | sed -e 's/\//-/g')

  pushd versioned-docs
  for app in "${APPS[@]}"; do
    pushd ${app}
    gsutil -m -h "cache-control: public,max-age=3600" -h "x-goog-meta-surrogate-key: docspage/${app}/${version}" -h "x-goog-meta-surrogate-control: public,max-age=604800" cp -r . "gs://hexdocs.pm/${app}/${version}"
    fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}/${version}"

    gsutil -m -h "cache-control: public,max-age=3600" -h "x-goog-meta-surrogate-key: docspage/${app}/docs_config.js" -h "x-goog-meta-surrogate-control: public,max-age=604800" cp docs_config.js "gs://hexdocs.pm/${app}"
    fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}/docs_config.js"

    popd

    tar -czf "${app}-${version}.tar.gz" -C "${app}" .
    aws s3 cp "${app}-${version}.tar.gz" "s3://s3.hex.pm/docs/${app}-${version}.tar.gz" --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docs/${app}-${version}\",\"surrogate-control\":\"public,max-age=604800\"}"
    fastly_purge $BOB_FASTLY_SERVICE_HEXPM "docs/${app}-${version}"
  done
  popd

  if [ -d unversioned-docs ]; then
    pushd unversioned-docs
    for app in "${APPS[@]}"; do
      pushd ${app}
      gsutil -m -h "cache-control: public,max-age=3600" -h "x-goog-meta-surrogate-key: docspage/${app}" -h "x-goog-meta-surrogate-control: public,max-age=604800" cp -r . "gs://hexdocs.pm/${app}"
      fastly_purge $BOB_FASTLY_SERVICE_HEXDOCS "docspage/${app}"
      popd
    done
    popd
  fi
}

echo "Building $1 $2 ${@:3}"
push "$1" "$2" ${@:3}
