FROM ubuntu:14.04

ARG otp_version

RUN apt-get update
RUN apt-get install -y git make wget zip

RUN mkdir -p /otp
RUN wget -nv -O otp.tar.gz https://repo.hex.pm/builds/otp/ubuntu-14.04/OTP-${otp_version}.tar.gz && tar zxf otp.tar.gz -C /otp --strip-components=1
RUN /otp/Install -minimal /otp

ENV OTP_VERSION=$otp_version
ENV PATH=/otp/bin:$PATH
ENV LANG=C.UTF-8

RUN mkdir -p /home/build
WORKDIR /home/build

COPY elixir/build_elixir.sh /home/build/build.sh
COPY utils.sh /home/build/utils.sh
COPY latest_version.exs /home/build/latest_version.exs
COPY elixir_to_ex_doc.exs /home/build/elixir_to_ex_doc.exs
COPY tags_to_versions.exs /home/build/tags_to_versions.exs
COPY build_docs_config.exs /home/build/build_docs_config.exs
COPY elixir/elixir_logo.png /home/build/logo.png
RUN chmod +x /home/build/build.sh
CMD ./build.sh
