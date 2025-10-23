#!/bin/bash

set -euox pipefail

rm -rf logs* || true
mkdir -p hex-s3
mkdir -p logs

today=$(date "+%Y-%m-%d")
yesterday=$(date "+%Y-%m-%d" --date=yesterday)

echo "### s3 ###"
aws s3 sync s3://s3.hex.pm hex-s3 --delete --include "*" --exclude "builds/*" > /dev/null

echo ""
echo "### logs fastly ###"
gsutil -qm cp "gs://hexpm-logs-prod/fastly_hex/${yesterday}T*" logs
pigz -d -c logs/*.gz | pigz -9 -c - > logs-fastly.txt.gz

echo ""
echo "### upload ###"
tarsnap -d -f hex-s3-${today}.part || true
tarsnap -c -f hex-s3-${today} hex-s3
gsutil -q cp logs-fastly.txt.gz gs://hexpm-backup/logs/daily/hex-fastly-${yesterday}.txt.gz

echo ""
echo "### clean up ###"
rm -rf logs*
