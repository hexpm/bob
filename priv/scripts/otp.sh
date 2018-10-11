#!/bin/bash

set -e -u

ref_name=$1
ref=$2
linux=$3

source ${SCRIPT_DIR}/utils.sh

container="otp-build-${linux}-${ref_name}"
image="gcr.io/hexpm-prod/bob-otp"
tag=${linux}

docker pull ${image}:${tag} || true
docker build -t ${image}:${tag} -f ${SCRIPT_DIR}/otp-${linux}.dockerfile ${SCRIPT_DIR}
docker push ${image}:${tag}
docker rm ${container} || true
docker run -t -e OTP_REF=${ref_name} --name=${container} ${image}:${tag}

docker cp ${container}:/home/build/out/${ref_name}.tar.gz ${ref_name}.tar.gz

aws s3 cp ${ref_name}.tar.gz s3://s3.hex.pm/builds/otp/${linux}/${ref_name}.tar.gz --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"otp-builds","surrogate-control":"public,max-age=604800"}'

aws s3 cp s3://s3.hex.pm/builds/otp/${linux}/builds.txt builds.txt || true
touch builds.txt
sed -i '/^${ref_name} /d' builds.txt
echo -e "${ref_name} ${ref}\n$(cat builds.txt)" > builds.txt
sort -u -k1,1 -o builds.txt builds.txt
aws s3 cp builds.txt s3://s3.hex.pm/builds/otp/${linux}/builds.txt --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"otp-builds","surrogate-control":"public,max-age=604800"}'

fastly_purge_path builds/otp/${linux}/${ref_name}.tar.gz
fastly_purge_path builds/otp/${linux}/builds.txt
