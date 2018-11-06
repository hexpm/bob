#!/bin/bash

set -e -u

version=$(echo "${HEX_REF}" | sed 's/^v//g')

git clone git://github.com/elixir-lang/ex_doc.git --quiet
pushd ex_doc
echo "Building ExDoc"
ex_doc_version=master
git checkout "${ex_doc_version}"
mix deps.get
mix compile --no-elixir-version-check
popd

git clone git://github.com/hexpm/hex.git --quiet --branch "${HEX_REF}"
pushd hex
mkdir docs
mix compile
echo "Building docs"

pwd

../ex_doc/bin/ex_doc \
  Hex "$version" \
  _build/dev/lib/hex/ebin \
  -u https://github.com/hexpm/hex \
  -m Mix.Tasks.Hex \
  --logo ${SCRIPT_DIR}/hex_logo.png \
  --source-ref "$HEX_REF"

cp -R doc ../versioned-docs

tags=$(git tag)
latest_version=$(elixir ${SCRIPT_DIR}/latest_version.exs "${tags}")

if [ "${version}" == "${latest_version}" ]; then
  mv doc ../unversioned-docs
fi

popd
