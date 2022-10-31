FROM hexpm/elixir:1.14.1-erlang-25.1.2-ubuntu-jammy-20220428

ENV LANG=C.UTF-8

RUN apt update
RUN apt install -y git

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir -p /home/build
WORKDIR /home/build

COPY hex/build_hex_docs.sh /home/build/build.sh
COPY utils.sh /home/build/utils.sh
COPY latest_version.exs /home/build/latest_version.exs
COPY elixir_to_ex_doc.exs /home/build/elixir_to_ex_doc.exs
COPY tags_to_versions.exs /home/build/tags_to_versions.exs
COPY build_docs_config.exs /home/build/build_docs_config.exs
COPY hex/hex_logo.png /home/build/logo.png
RUN chmod +x /home/build/build.sh
CMD ./build.sh
