FROM alpine:3.10

RUN apk --no-cache upgrade

RUN apk add --no-cache \
    dpkg-dev \
    dpkg \
    wget \
    bash \
    pcre \
    ca-certificates \
    openssl-dev \
    ncurses-dev \
    unixodbc-dev \
    zlib-dev \
    autoconf \
    build-base \
    perl-dev \
    libstdc++

RUN mkdir -p /home/build/out
WORKDIR /home/build

COPY otp/build_otp_alpine.sh /home/build/build.sh
RUN chmod +x /home/build/build.sh
CMD ./build.sh
