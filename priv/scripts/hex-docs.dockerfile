FROM ubuntu:14.04

ARG otp_version=21.0
ARG otp_major=21
ARG elixir_version=v1.7.3

RUN apt-get update
RUN apt-get install -y git make wget zip

RUN wget -nv -O otp.tar.gz https://repo.hex.pm/builds/otp/ubuntu-14.04/OTP-${otp_version}.tar.gz
RUN mkdir -p /otp
RUN tar zxf otp.tar.gz -C /otp --strip-components=1
RUN /otp/Install -minimal /otp

RUN wget -nv -O elixir.zip https://repo.hex.pm/builds/elixir/${elixir_version}-otp-${otp_major}.zip
RUN unzip -d /elixir elixir.zip

ENV PATH=/otp/bin:/elixir/bin:$PATH
RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir -p /home/build/out
WORKDIR /home/build

COPY build_hex_docs.sh /home/build/build.sh
COPY utils.sh /home/build/utils.sh
COPY latest_version.exs /home/build/latest_version.exs
COPY elixir_to_ex_doc.exs /home/build/elixir_to_ex_doc.exs
COPY hex_logo.png /home/build/logo.png
RUN chmod +x /home/build/build.sh
CMD ./build.sh
