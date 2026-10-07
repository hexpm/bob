#!/bin/bash

set -euox pipefail

repo=$1
tag=$2

# Sign the digest that was pushed, since the tag can be moved
digest=sha256:$(docker buildx imagetools inspect --raw ${repo}:${tag} | sha256sum | cut -d ' ' -f 1)

# Cloud KMS is called as the service account whose key Bob.Application writes here
export GOOGLE_APPLICATION_CREDENTIALS=/boto/keyfile.json

# This command has a tendency to intermittently fail
cosign sign --yes --key ${BOB_COSIGN_KEY} ${repo}@${digest} ||
  (sleep $((20 + $RANDOM % 40)) && cosign sign --yes --key ${BOB_COSIGN_KEY} ${repo}@${digest}) ||
  (sleep $((20 + $RANDOM % 40)) && cosign sign --yes --key ${BOB_COSIGN_KEY} ${repo}@${digest}) ||
  (sleep $((20 + $RANDOM % 40)) && cosign sign --yes --key ${BOB_COSIGN_KEY} ${repo}@${digest}) ||
  (sleep $((20 + $RANDOM % 40)) && cosign sign --yes --key ${BOB_COSIGN_KEY} ${repo}@${digest}) ||
  (exit 1)
