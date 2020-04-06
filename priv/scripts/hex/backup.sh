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
# -m flag seems to crash with OOM, we may need to raise memory limits or
# figure out what is using all the memory.
# Fortunately latency is low so -m flag does not do much.
gsutil -q cp "gs://hexpm-logs-prod/fastly_hex/${yesterday}T*" logs
gunzip -c logs/*.gz | gzip -9 -c - > logs-fastly.txt.gz

echo ""
echo "### upload ###"
tarsnap -c -f hex-s3-${today} hex-s3
aws s3 cp logs-fastly.txt.gz s3://backup.hex.pm/logs/daily/hex-fastly-${yesterday}.txt.gz

echo ""
echo "### clean up ###"
rm -rf logs*
