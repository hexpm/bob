#!/bin/bash

set -e -u

# $1 = version
# $2 = ref

cwd=$(pwd)
scripts="${cwd}/../../scripts"
linux="ubuntu-14.04"

# $1 = service
# $2 = key
function fastly_purge {
  curl -X PURGE https://repo.hex.pm/${1}
}

cp ${scripts}/otp-${linux}.dockerfile .
cp ${scripts}/build_otp.sh .

docker rm $(docker ps -aq) || true
docker build -t otp-build -f otp-${linux}.dockerfile .
docker run -t -e OTP_REF=${1} --name=otp-build-${linux}-${1} otp-build

docker cp otp-build-${linux}-${1}:/home/build/out/${1}.tar.gz ${1}.tar.gz

aws s3 cp ${1}.tar.gz s3://s3.hex.pm/builds/otp/${linux}/${1}.tar.gz --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"otp-builds","surrogate-control":"public,max-age=604800"}'

aws s3 cp s3://s3.hex.pm/builds/otp/${linux}/builds.txt builds.txt
echo -e "${1} ${2}\n$(cat builds.txt)" > builds.txt
sort -u -k1,1 -o builds.txt builds.txt
aws s3 cp builds.txt s3://s3.hex.pm/builds/otp/${linux}/builds.txt --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"otp-builds","surrogate-control":"public,max-age=604800"}'

fastly_purge builds/otp/${linux}/${1}.tar.gz
fastly_purge builds/otp/${linux}/builds.txt
