#!/bin/bash

set -e -u

git clone git://github.com/elixir-lang/elixir.git --quiet --depth 1 --single-branch
git clone git://github.com/elixir-lang/ex_doc.git --quiet --depth 1 --single-branch
git clone https://${BOB_GITHUB_TOKEN}@github.com/elixir-lang/docs.git

PATH=$(pwd)/elixir/bin:${PATH}
MIX_ARCHIVES=$(pwd)/.mix

pushd elixir
make compile
popd

mix local.hex --force

pushd ex_doc
mix do deps.get, compile
popd

pushd elixir
make publish_docs
popd

pushd docs
git add --all
git commit --allow-empty -m "Nightly build"
git push
popd
