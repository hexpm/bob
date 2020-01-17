# Bob the builder

Bob performs automated tasks for the Elixir and Hex projects.

## Elixir builds

Elixir builds are compiled on each git push to https://github.com/elixir-lang/elixir for any branch. After the build completes it will be available at `https://repo.hex.pm/builds/elixir/{REF}.zip` where `{REF}` is the git ref for that push. Examples of URLs are:

  * https://repo.hex.pm/builds/elixir/master.zip
  * https://repo.hex.pm/builds/elixir/v1.4.5.zip

These Elixir builds will be compiled against the oldest supported OTP version to ensure maximum compatibility for all users. We also build Elixir for every officially supported OTP version, if possible always use an Elixir compiled against the latest OTP version to get all available features in Elixir. These builds are available at `https://repo.hex.pm/builds/elixir/{REF}-otp-{OTP_MAJOR_VERSION}.zip`, examples are:

  * https://repo.hex.pm/builds/elixir/master-otp-20.zip
  * https://repo.hex.pm/builds/elixir/v1.4.5-otp-19.zip

Since these builds are only available for officially supported OTP versions it is recommended that you fall back to the non OTP versioned URL if you get a 404 error for your combination of Elixir and OTP versions. Check https://github.com/hexpm/bob/blob/master/lib/bob/job/build_elixir.ex to find which OTP versions we build against for particular Elixir versions.

See https://repo.hex.pm/builds/elixir/builds.txt for a list of all builds.

## Elixir docs

On git pushes documentation is built and pushed to `https://hexdocs.pm/{APPLICATION}/{VERSION}` where `{APPLICATION}` is an application in the Elixir standard distribution and `{VERSION}` is the Elixir version, examples are:

  * https://hexdocs.pm/elixir/
  * https://hexdocs.pm/elixir/master
  * https://hexdocs.pm/mix/1.4.5

Documentation tarballs are also uploaded to `https://repo.hex.pm/docs/{APPLICATION}-{VERSION}.tar.gz`, examples are:

  * https://repo.hex.pm/docs/elixir-master.tar.gz
  * https://repo.hex.pm/docs/mix-1.4.5.tar.gz

## Erlang builds

Erlang builds compiled on Ubuntu 14.04 and Alpine 3.10 are built periodically. Bob checks for new tagged releases every 15 minutes and builds any new versions it discovers. The "master" and "maint*" branches are built once a day.

After the builds complete they will be available at `https://repo.hex.pm/builds/otp/${OS_VER}/{REF}.tar.gz` where `{REF}` is the name of the git tag or branch. Examples of URLs are:

  * https://repo.hex.pm/builds/otp/ubuntu-14.04/master.tar.gz
  * https://repo.hex.pm/builds/otp/alpine-3.10/OTP-22.tar.gz

For lists of builds see:

  * https://repo.hex.pm/builds/otp/ubuntu-14.04/builds.txt
  * https://repo.hex.pm/builds/otp/alpine-3.10/builds.txt

## Docker images

**NOTE: Docker images are currently considered experimental while they are being tested for production worthiness!**

Docker images for Bob's Elixir and Erlang builds are built periodically. Bob checks for new Elixir and Erlang releases every 15 minutes and builds images for any new versions it discovers. The images are based on [Alpine Linux](https://alpinelinux.org/), they will usually build against the latest stable Alpine version, builds against older versions will not be provided.

Tagged images are never changed, that means `hexpm/erlang@22.0-alpine-3.11.2` will always target the tag `OTP-22.0` and won't update when `OTP-22.0.1` is released.

Erlang builds are found at https://hub.docker.com/r/hexpm/erlang, they use the versioning scheme `${OTP_VER}-alpine-${ALPINE_VER}` for tags. Builds for all major releases since OTP 19 are provided. Images are not built for sub-patch releases, for example `OTP-22.1.8.1`.

Elixir builds are found at https://hub.docker.com/r/hexpm/elixir, they use the versioning scheme `${ELIXIR_VER}-erlang-${OTP_VER}-alpine-${ALPINE_VER}`. Builds for all major releases since Elixir 1.3.0 are provided. Images are built for all pairs of compatible Elixir and OTP versions.

## Hex S3 backups

Each days backups of yesterdays access logs stored on the bucket `logs.hex.pm` is uploaded to the bucket `backup.hex.pm`.

A snapshot of the bucket `s3.hex.pm` is also uploaded to [tarsnap](https://www.tarsnap.com).
