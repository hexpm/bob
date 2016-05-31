#!/bin/bash

set -e -u

rm -rf logs* || true
mkdir -p hex-s3
mkdir -p logs

today=$(date "+%Y-%m-%d")
yesterday=$(date "+%Y-%m-%d" --date=yesterday)

echo "### s3 ###"
aws s3 sync s3://s3.hex.pm hex-s3 --delete --include "*" --quiet

echo ""
echo "### logs s3 ###"
aws s3 cp s3://logs.hex.pm      logs                         --recursive --exclude "*" --include "hex/${yesterday}-*" --quiet
aws s3 cp s3://logs-eu.hex.pm   logs --region eu-west-1      --recursive --exclude "*" --include "hex/${yesterday}-*" --quiet
aws s3 cp s3://logs-asia.hex.pm logs --region ap-southeast-1 --recursive --exclude "*" --include "hex/${yesterday}-*" --quiet
echo logs/hex/* | xargs cat > logs-s3.txt
gzip -9 logs-s3.txt

echo ""
echo "### logs fastly ###"
aws s3 cp s3://logs.hex.pm logs --recursive --exclude "*" --include "fastly_hex/${yesterday}T*" --quiet
echo logs/fastly_hex/*.gz | xargs gunzip
echo logs/fastly_hex/* | xargs cat > logs-fastly.txt
gzip -9 logs-fastly.txt

echo ""
echo "### upload ###"
tarsnap -c -f hex-s3-${today} hex-s3
aws s3 cp logs-s3.txt.gz s3://backup.hex.pm/logs/daily/hex-s3-${yesterday}.txt
aws s3 cp logs-fastly.txt.gz s3://backup.hex.pm/logs/daily/hex-fastly-${yesterday}.txt

echo ""
echo "### clean up ###"
rm -rf logs*
