FROM ubuntu:16.04

RUN apt-get update

RUN apt-get install -y curl wget ca-certificates
RUN apt-get install -y gcc g++
RUN apt-get install -y make automake autoconf
RUN apt-get install -y libwxgtk3.0-dev libgl1-mesa-dev libglu1-mesa-dev libpng3
RUN apt-get install -y libreadline-dev libncurses-dev libssl-dev libssh-dev
RUN apt-get install -y libxslt-dev libffi-dev libtool unixodbc-dev
RUN apt-get install -y fop xsltproc

RUN mkdir -p /home/build/out
WORKDIR /home/build

COPY build_otp.sh /home/build/build.sh
RUN chmod +x /home/build/build.sh
CMD ./build.sh
