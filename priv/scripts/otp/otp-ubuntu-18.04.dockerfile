FROM ubuntu:18.04

ENV UBUNTU_VERSION=18.04
ARG OTP_REF

RUN apt-get update
RUN apt-get install -y \
  wget \
  ca-certificates \
  gcc \
  g++ \
  make \
  automake \
  autoconf \
  libwxgtk3.0-gtk3-dev \
  libgl1-mesa-dev \
  libglu1-mesa-dev \
  libpng-dev \
  libreadline-dev \
  libncurses-dev \
  $(bash -c 'if [ "${OTP_REF:0:5}" = "OTP-1" ]; then echo "libssl1.0-dev"; else echo "libssl-dev"; fi') \
  libxslt-dev \
  libffi-dev \
  libtool \
  unixodbc-dev \
  fop \
  xsltproc

RUN mkdir -p /home/build/out
WORKDIR /home/build

COPY otp/build_otp_ubuntu.sh /home/build/build.sh
RUN chmod +x /home/build/build.sh
CMD ./build.sh
