#!/bin/bash

set -e -u

APPS=(hexpm hexpm-billing hexpm-staging hexpm-billing-staging)
today=$(date "+%Y-%m-%d")

for app in "${APPS[@]}"; do
  echo "BACKING UP ${app}"
  heroku pg:backups:capture -a ${app}
  heroku pg:backups:download -a ${app} -o ${app}-${today}.dump
  aws s3 cp ${app}-${today}.dump s3://backup.hex.pm/dbs/daily/${app}-${today}.dump
done
