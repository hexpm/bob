# Public API

Bob provides read-only JSON endpoints for searching build artifacts and Docker tags. The API is available at `https://bob.hex.pm` and doesn't require authentication.

Both endpoints return at most 100 results at a time. Pass a positive integer as the `offset` query parameter to fetch the next page. Missing, zero, negative, and invalid offsets are treated as `0`.

Every response includes:

| Field | Description |
| --- | --- |
| `total` | Number of records matching the filters. |
| `offset` | Offset used for the current page. |
| `page_size` | Maximum number of records returned per page. This is always `100`. |

Results are ordered by build time, newest first, unless an endpoint documents another sort option.

## Build artifacts

`GET /api/artifacts` searches OTP build artifacts.

### Query parameters

| Parameter | Matching behavior |
| --- | --- |
| `query` | Case-insensitive substring match against `name` and `ref`. |
| `kind` | Exact match against the artifact kind. |
| `arch` | Exact match against the CPU architecture. |
| `os` | Exact match against the operating system name and version. |
| `offset` | Number of matching records to skip. Defaults to `0`. |

When multiple filters are present, a result must match all of them.

```console
curl --get \
  --header 'accept: application/json' \
  --data-urlencode 'kind=otp' \
  --data-urlencode 'arch=amd64' \
  --data-urlencode 'os=ubuntu-24.04' \
  https://bob.hex.pm/api/artifacts
```

The `artifacts` array contains objects with these fields:

| Field | Description |
| --- | --- |
| `kind` | Artifact kind. |
| `arch` | CPU architecture. |
| `os` | Operating system name and version. |
| `name` | Build name, such as an OTP tag or branch. |
| `ref` | Git revision used for the build. |
| `sha256` | SHA-256 checksum, or `null` for artifacts that predate checksum storage. |
| `built_at` | Build time as an ISO 8601 UTC timestamp. |

Example response, with all but the first matching artifact omitted:

```json
{
  "artifacts": [
    {
      "arch": "amd64",
      "built_at": "2026-08-04T11:10:04.000000Z",
      "kind": "otp",
      "name": "OTP-29.0.5",
      "os": "ubuntu-24.04",
      "ref": "5cf5f9725452f4e1b6a4890e8ff0305d76924b98",
      "sha256": "1ecf8a20104afa053e6701e36ec1485cbce1a2fa4aef962d5e73f9eb5c6e9fc0"
    }
  ],
  "offset": 0,
  "page_size": 100,
  "total": 168
}
```

## Docker tags

`GET /api/docker` searches tags in the Hex Docker repositories. Each filter uses a case-sensitive prefix match.

### Query parameters

| Parameter | Matching behavior |
| --- | --- |
| `repo` | Prefix match against the repository name. For example, `hexpm/elixir` also matches `hexpm/elixir-amd64` and `hexpm/elixir-arm64`. |
| `tag` | Prefix match against the full Docker tag. |
| `arch` | Prefix match against any architecture provided by the tag. |
| `elixir_version` | Prefix match against the Elixir version parsed from the tag. |
| `erlang_version` | Prefix match against the Erlang version parsed from the tag. |
| `os` | Prefix match against the operating system parsed from the tag. |
| `os_version` | Prefix match against the operating system version parsed from the tag. |
| `sort` | Comma-separated descending sort keys in precedence order: `elixir_version`, `erlang_version`, `os`, `os_version`, or `built_at`. Defaults to `built_at`. Version keys use numeric-aware ordering, with a stable release before prereleases of the same release. Build time and ID break remaining ties. |
| `offset` | Number of matching records to skip. Defaults to `0`. |

When multiple filters are present, a result must match all of them. If `tag` is present, the API ignores `elixir_version`, `erlang_version`, `os`, and `os_version`. The `repo` and `arch` filters still apply.

```console
curl --get \
  --header 'accept: application/json' \
  --data-urlencode 'repo=hexpm/elixir' \
  --data-urlencode 'elixir_version=1.18' \
  --data-urlencode 'erlang_version=27' \
  --data-urlencode 'os=ubuntu' \
  https://bob.hex.pm/api/docker
```

The `tags` array contains objects with these fields:

| Field | Description |
| --- | --- |
| `repo` | Docker repository name. |
| `tag` | Docker tag. |
| `archs` | Architectures provided by the tag. |
| `built_at` | Build time as an ISO 8601 UTC timestamp. |

Example response, with all but the first matching tag omitted:

```json
{
  "offset": 0,
  "page_size": 100,
  "tags": [
    {
      "archs": [
        "amd64",
        "arm64"
      ],
      "built_at": "2026-08-04T13:00:30.476813Z",
      "repo": "hexpm/elixir",
      "tag": "1.18.4-erlang-27.3.4.16-ubuntu-jammy-20260627"
    }
  ],
  "total": 3707
}
```
