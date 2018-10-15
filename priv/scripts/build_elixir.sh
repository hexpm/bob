#!/bin/bash

set -e -u

cwd=$(pwd)

if [ -z "${ELIXIR_REF}" ]; then
  echo "ELIXIR_REF not set"
  exit 1
fi

git clone git://github.com/elixir-lang/elixir.git --quiet --branch "${ELIXIR_REF}"

pushd elixir
erl +V
make compile
make Precompiled.zip || make release_zip
mv *.zip ../elixir.zip
popd

if [ "${BUILD_DOCS}" == "1" ]; then
  version=$(echo "${ELIXIR_REF}" | sed 's/^v//g')

  PATH="$(pwd)/elixir/bin:${PATH}"
  elixir -v

  mix local.hex --force
  mkdir docs
  cp logo.png docs/logo.png

  git clone git://github.com/elixir-lang/ex_doc.git --quiet

  pushd ex_doc
  tags=$(git tag)
  latest_version=$(elixir ${cwd}/latest_version.exs "${tags}")
  ex_doc_version=$(elixir ${cwd}/elixir_to_ex_doc.exs "${ELIXIR_REF}" "${latest_version}")
  git checkout "${ex_doc_version}"
  mix deps.get
  mix compile --no-elixir-version-check
  popd

  pushd elixir

  sed -i -e 's/-n http:\/\/elixir-lang.org\/docs\/\$(CANONICAL)\/\$(2)\//-n https:\/\/hexdocs.pm\/\$(2)\/\$(CANONICAL)/g' Makefile
  sed -i -e 's/-a http:\/\/elixir-lang.org\/docs\/\$(CANONICAL)\/\$(2)\//-a https:\/\/hexdocs.pm\/\$(2)\/\$(CANONICAL)/g' Makefile
  CANONICAL="${version}" make docs
  mv doc ../versioned-docs

  tags=$(git tag)
  latest_version=$(elixir ${cwd}/latest_version.exs "${tags}")

  if [ "${version}" == "${latest_version}" ]; then
    CANONICAL="" make docs
    mv doc ../unversioned-docs
  fi

  popd
fi
