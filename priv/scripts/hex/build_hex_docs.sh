#!/bin/bash

set -euox pipefail

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
mix compile
echo "Building docs"

../ex_doc/bin/ex_doc \
  Hex "$version" \
  _build/dev/lib/hex/ebin \
  -u https://github.com/hexpm/hex \
  -m Mix.Tasks.Hex \
  --logo ../logo.png \
  --source-ref "$HEX_REF"

cp -R doc ../versioned-docs

tags=$(git tag)
latest_version=$(elixir ../latest_version.exs "${tags}")

if [ "${version}" == "${latest_version}" ]; then
  mv doc ../unversioned-docs
fi

versions=$(elixir ../tags_to_versions.exs "${tags}" 0.17.0)
elixir ../build_docs_config.exs hex "${versions}"
mv docs_config.js ../versioned-docs

popd
