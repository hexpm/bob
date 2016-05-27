#!/bin/sh

set -e -u

mkdir -p "hex-s3"
rm -rf logs-fastly || true
rm -rf logs-s3 || true

today=$(date "+%Y-%m-%d")
yesterday=$(date "+%Y-%m-%d" --date=yesterday)

echo "### s3 ###"
aws s3 sync s3://s3.hex.pm hex-s3 --delete --include "*" --quiet

echo ""
echo "### logs s3 ###"
mkdir -p logs-s3
aws s3 cp s3://logs.hex.pm      logs-s3                                --recursive --exclude "*" --include "hex/${yesterday}-*" --quiet
aws s3 cp s3://logs-eu.hex.pm   logs-s3 --source-region eu-west-1      --recursive --exclude "*" --include "hex/${yesterday}-*" --quiet
aws s3 cp s3://logs-asia.hex.pm logs-s3 --source-region ap-southeast-1 --recursive --exclude "*" --include "hex/${yesterday}-*" --quiet
echo logs-s3/* | xargs cat > logs-s3.txt
gzip -9 logs-s3.txt

echo ""
echo "### logs fastly ###"
mkdir -p logs-fastly
aws s3 cp s3://logs.hex.pm logs-fastly --recursive --exclude "*" --include "fastly_hex/${yesterday}-*" --quiet
echo logs-fastly/*.gz | xargs gunzip
echo logs-fastly/* | xargs cat > logs-fastly.txt
gzip -9 logs-fastly.txt

echo ""
echo "### upload ###"
tarsnap -c -f hex-s3-${today} hex-s3
aws s3 cp logs-s3.txt.gz s3://backup.hex.pm/logs/daily/hex-s3-${yesterday}.txt
aws s3 cp logs-fastly.txt.gz s3://backup.hex.pm/logs/daily/hex-fastly-${yesterday}.txt

echo ""
echo "### clean up ###"
rm -rf logs-s3* logs-fastly*
