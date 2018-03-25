#!/bin/bash

set -e -u
#!/bin/bash
APPS=(hexpm hexpm-billing hexpm-staging hexpm-billing-staging)
today=$(date "+%Y-%m-%d")

for app in "${APPS[@]}"; do
  echo "BACKING UP ${app}"
  heroku pg:backups:capture -a ${app}
  heroku pg:backups:download -a ${app} -o ${app}-${today}.dump
  tarsnap -c -f dbdump-${app}-${today} ${app}-${today}.dump
done
