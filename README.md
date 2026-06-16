# Bob the builder

Bob performs automated tasks for the Elixir and Hex projects.

## Erlang builds

Erlang builds compiled on Ubuntu LTS versions are built periodically. Bob checks for new tagged releases every 15 minutes and builds any new versions it discovers. The "master" and "maint*" branches are built once a day.

After the builds complete they will be available at `https://builds.hex.pm/builds/otp/${ARCH}/${OS_VER}/${REF}.tar.gz` where `${ARCH}` is the CPU architecture, `${OS_VER}` is the OS name and version, and `${REF}` is the name of the git tag or branch.

Supported architectures:

  * `amd64`
  * `arm64`

Supported OS versions:

  * `ubuntu-22.04`
  * `ubuntu-24.04`
  * `ubuntu-26.04`

Examples of URLs are:

  * https://builds.hex.pm/builds/otp/arm64/ubuntu-22.04/OTP-26.0.tar.gz
  * https://builds.hex.pm/builds/otp/amd64/ubuntu-24.04/maint.tar.gz

For lists of builds see:

  * `amd64`:
    * https://builds.hex.pm/builds/otp/amd64/ubuntu-22.04/builds.txt
    * https://builds.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt
    * https://builds.hex.pm/builds/otp/amd64/ubuntu-26.04/builds.txt
  * `arm64`:
    * https://builds.hex.pm/builds/otp/arm64/ubuntu-22.04/builds.txt
    * https://builds.hex.pm/builds/otp/arm64/ubuntu-24.04/builds.txt
    * https://builds.hex.pm/builds/otp/arm64/ubuntu-26.04/builds.txt

## Docker images

Docker images for Bob's Elixir and Erlang builds are built periodically. Bob checks for new Elixir and Erlang releases every 15 minutes and builds images for any new versions it discovers. The list of operating system distributions we base the images on is defined by `builds/0` in https://github.com/hexpm/bob/blob/main/lib/bob/job/docker_checker.ex.

Bob automatically builds the latest patch release of every version family: the newest release per Erlang `major.minor` line (for example only `26.2.5.21` out of the `26.2.x` line) and the newest Elixir patch release per minor version, for every compatible OTP major. Older patch versions are not built automatically but can be requested manually, see below.

Tagged images are never changed, that means `hexpm/erlang@22.0-alpine-3.11.2` will always target the tag `OTP-22.0` and won't update when `OTP-22.0.1` is released.

Erlang builds are found at https://hub.docker.com/r/hexpm/erlang, they use the versioning scheme `${OTP_VER}-${OS_NAME}-${OS_VER}` for tags.

Elixir builds are found at https://hub.docker.com/r/hexpm/elixir, they use the versioning scheme `${ELIXIR_VER}-erlang-${OTP_VER}-${OS_NAME}-${OS_VER}`.

Builds are provided for the following OS and architectures using the docker `OS/ARCH` scheme:

* `linux/amd64`
* `linux/arm64/v8`

All provided images and tags can be searched at https://bob.hex.pm/docker.

### Examples of image names

 * `hexpm/erlang:22.2.8-alpine-3.11.3`
 * `hexpm/erlang:22.2-ubuntu-bionic-20200219`
 * `hexpm/elixir:1.10.2-erlang-22.2.8-alpine-3.11.3`
 * `hexpm/elixir:1.10.0-erlang-22.2-ubuntu-bionic-20200219`

### Requesting builds

If you need a specific patch version that is not built automatically, request it at https://bob.hex.pm/request. Sign in with your hex.pm account, then pick the image kind (Erlang or Elixir), the OS and base image version, and the exact Erlang (and Elixir) version. The image is built for both architectures, including the multi-arch manifest; when an Elixir image needs an Erlang base image that does not exist yet, the base is built first and the Elixir image follows automatically.

Requested builds are limited to ten image builds per user per hour. Build progress can be followed on the jobs dashboard at https://bob.hex.pm.
