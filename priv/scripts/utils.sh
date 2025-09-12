# $1 = service
# $2 = keys
function fastly_purge {
  fastly_purge_request $1 "$2"
  sleep 4
  fastly_purge_request $1 "$2"
  sleep 4
  fastly_purge_request $1 "$2"
}

# $1 = service
# $2 = keys
function fastly_purge_request {
  curl \
    --fail \
    -X POST \
    -H "Fastly-Key: ${BOB_FASTLY_KEY}" \
    -H "Accept: application/json" \
    -H "Content-Length: 0" \
    -H "surrogate-key: ${2}" \
    "https://api.fastly.com/service/${1}/purge"
}

