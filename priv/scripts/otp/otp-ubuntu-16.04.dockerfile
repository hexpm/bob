FROM ubuntu:16.04

ENV UBUNTU_VERSION=16.04

ARG PIE_CFLAGS="-fpie"
ARG CFLAGS="-g -O2 ${PIE_CFLAGS}"
ARG CPPFLAGS="-D_FORTIFY_SOURCE=2"

ARG PIE_LDFLAGS="-pie"
ARG LDFLAGS="-Wl,-z,relro,-z,now ${PIE_LDFLAGS}"

RUN apt-get update

RUN apt-get install -y \
  wget \
  ca-certificates \
  gcc \
  g++ \
  make \
  automake \
  autoconf \
  libwxgtk3.0-dev \
  libgl1-mesa-dev \
  libglu1-mesa-dev \
  libpng-dev \
  libreadline-dev \
  libncurses-dev \
  libssl-dev \
  libxslt-dev \
  libffi-dev \
  libtool \
  unixodbc-dev \
  fop \
  xsltproc

RUN mkdir -p /home/build/out
WORKDIR /home/build

ENV CFLAGS=$CFLAGS
ENV CPPFLAGS=$CPPFLAGS
ENV LDFLAGS=$LDFLAGS

COPY otp/build_otp_ubuntu.sh /home/build/build.sh
RUN chmod +x /home/build/build.sh
CMD ./build.sh
