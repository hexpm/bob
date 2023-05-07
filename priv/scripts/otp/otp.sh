#!/bin/bash

set -euox pipefail

ref_name=$1
ref=$2
linux=$3

source ${SCRIPT_DIR}/utils.sh

echo "Building $1 $2 $3"

container="otp-build-${linux}-${ref_name}"
image="bob-otp"
tag=${linux}
date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Disable PIE for OTP prior to 21; see http://erlang.org/doc/apps/hipe/notes.html#hipe-3.18
pie_cflags="-fpie"
pie_ldflags="-pie"
if [ "$(echo ${ref_name} | cut -d '-' -f 2 | cut -d '.' -f 1)" -le "20" ]; then
  pie_cflags=""
  pie_ldflags=""
fi

docker build \
    -t ${image}:${tag} \
    --build-arg OTP_REF=${ref_name} \
    --build-arg PIE_CFLAGS=${pie_cflags} \
    --build-arg PIE_LDFLAGS=${pie_ldflags} \
    -f ${SCRIPT_DIR}/otp/otp-${linux}.dockerfile ${SCRIPT_DIR}
docker rm -f ${container} || true
docker run -t -e OTP_REF=${ref_name} --name=${container} ${image}:${tag}

docker cp ${container}:/home/build/out/${ref_name}.tar.gz ${ref_name}.tar.gz

docker rm -f ${container}

aws s3 cp ${ref_name}.tar.gz s3://s3.hex.pm/builds/otp/${linux}/${ref_name}.tar.gz --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"otp-builds-${linux}-${ref_name}\",\"surrogate-control\":\"public,max-age=604800\"}"

aws s3 cp s3://s3.hex.pm/builds/otp/${linux}/builds.txt builds.txt || true
touch builds.txt
sed -i "/^${ref_name} /d" builds.txt
echo -e "${ref_name} ${ref} $(date -u '+%Y-%m-%dT%H:%M:%SZ')\n$(cat builds.txt)" > builds.txt
sort -u -k1,1 -o builds.txt builds.txt
aws s3 cp builds.txt s3://s3.hex.pm/builds/otp/${linux}/builds.txt --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"otp-builds-txt","surrogate-control":"public,max-age=604800"}'

fastly_purge $BOB_FASTLY_SERVICE_HEXPM "otp-builds-txt otp-builds-${linux}-${ref_name}"
