# Bob the builder

Bob performs automated tasks for the Elixir and Hex projects.

## Elixir builds

Elixir builds are compiled on each git push to https://github.com/elixir-lang/elixir for any branch. After the build completes it will be available at `https://repo.hex.pm/builds/elixir/{REF}.zip` where `{REF}` is the git ref for that push. Examples of URLs are:

  * https://repo.hex.pm/builds/elixir/master.zip
  * https://repo.hex.pm/builds/elixir/v1.4.5.zip

These Elixir builds will be compiled against the oldest supported OTP version to ensure maximum compatibility for all users. We also build Elixir for every officially supported OTP version, if possible always use an Elixir compiled against the latest OTP version to get all available features in Elixir. These builds are available at `https://repo.hex.pm/builds/elixir/{REF}-otp-{OTP_MAJOR_VERSION}.zip`, examples are:

  * https://repo.hex.pm/builds/elixir/master-otp-20.zip
  * https://repo.hex.pm/builds/elixir/v1.4.5-otp-19.zip

Since these builds are only available for officially supported OTP versions it is recommended that you fall back to the non OTP versioned URL if you get a 404 error for your combination of Elixir and OTP versions. Check https://github.com/hexpm/bob/blob/master/scripts/elixir_to_otp.exs to find which OTP versions we build against for particular Elixir versions.

## Elixir docs

On  git pushes documentation is built and pushed to `https://hexdocs.pm/{APPLICATION}/{VERSION}` where `{APPLICATION}` is an application in the Elixir standard distribution and `{VERSION}` is the Elixir version, examples are:

  * https://hexdocs.pm/elixir/
  * https://hexdocs.pm/elixir/master
  * https://hexdocs.pm/mix/1.4.5

Documentation tarballs are also uploaded to https://repo.hex.pm/docs/{APPLICATION}-{VERSION}.tar.gz, examples are:

  * https://repo.hex.pm/docs/elixir-master.tar.gz
  * https://repo.hex.pm/docs/mix-1.4.5.tar.gz

## Hex S3 backups

Each days backups of yesterdays access logs stored on the buckets:

  * `logs.hex.pm`
  * `logs-eu.hex.pm`
  * `logs-asia.hex.pm`

are uploaded to the bucket `backup.hex.pm`.

A snapshot of the bucket `s3.hex.pm` is also uploaded to [tarsnap](https://www.tarsnap.com).
