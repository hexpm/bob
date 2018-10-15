#!/bin/bash

set -e -u

git clone git://github.com/elixir-lang/elixir-lang.github.com.git --quiet --branch master

pushd elixir-lang.github.com/_epub
mix deps.get
mix compile
mix epub
popd

mkdir epub
mv elixir-lang.github.com/_epub/*.epub epub
