# $1 = service
# $2 = key
function fastly_purge {
  curl \
    -X POST \
    -H "Fastly-Key: ${BOB_FASTLY_KEY}" \
    -H "Accept: application/json" \
    -H "Content-Length: 0" \
    "https://api.fastly.com/service/${1}/purge/${2}"
}

# $1 = path
function fastly_purge_repo_path {
  curl -X PURGE https://repo.hex.pm/${1}
}

# $1 = path
function fastly_purge_hexdocs_path {
  curl -X PURGE https://hexdocs.pm/${1}
}
