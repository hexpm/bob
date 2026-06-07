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

Docker images for Bob's Elixir and Erlang builds are built periodically. Bob checks for new Elixir and Erlang releases every 15 minutes and builds images for any new versions it discovers. The list of operating system distributions we base the images on can be found here: https://github.com/hexpm/bob/blob/main/lib/bob/job/docker_checker.ex#L5.

Tagged images are never changed, that means `hexpm/erlang@22.0-alpine-3.11.2` will always target the tag `OTP-22.0` and won't update when `OTP-22.0.1` is released.

Erlang builds are found at https://hub.docker.com/r/hexpm/erlang, they use the versioning scheme `${OTP_VER}-${OS_NAME}-${OS_VER}` for tags. Builds for all releases since OTP 17 are provided.

Elixir builds are found at https://hub.docker.com/r/hexpm/elixir, they use the versioning scheme `${ELIXIR_VER}-erlang-${OTP_VER}-${OS_NAME}-${OS_VER}`. Builds for all major releases since Elixir 1.0.0 are provided. Images are built for all pairs of compatible Elixir and OTP versions.

Builds are provided for the following OS and architectures using the docker `OS/ARCH` scheme:

* `linux/amd64`
* `linux/arm64/v8`

### Examples of image names

 * `hexpm/erlang:22.2.8-alpine-3.11.3`
 * `hexpm/erlang:22.2-ubuntu-bionic-20200219`
 * `hexpm/elixir:1.10.2-erlang-22.2.8-alpine-3.11.3`
 * `hexpm/elixir:1.10.0-erlang-22.2-ubuntu-bionic-20200219`
