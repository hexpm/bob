ARG OS_VERSION

FROM ubuntu:${OS_VERSION} AS build

ARG ERLANG

RUN apt-get update
RUN apt-get -y --no-install-recommends install \
  autoconf \
  dpkg-dev \
  gcc \
  gcc-9 \
  g++ \
  make \
  libncurses-dev \
  unixodbc-dev \
  libssl-dev \
  libsctp-dev \
  wget \
  ca-certificates \
  pax-utils

RUN mkdir /OTP
RUN wget -nv "https://github.com/erlang/otp/archive/OTP-${ERLANG}.tar.gz" && tar -zxf "OTP-${ERLANG}.tar.gz" -C /OTP --strip-components=1
WORKDIR /OTP
RUN ./otp_build autoconf

RUN ./otp_build autoconf
# Work around "LD: multiple definition of" errors on GCC 10, issue fixed in OTP 22.3
RUN bash -c 'if [ "${ERLANG:0:1}" = "1" ] || [ "${ERLANG:0:2}" = "20" ] || [ "${ERLANG:0:2}" = "21" ] || [ "${ERLANG:0:2}" = "22" ] ; then CC=gcc-9 ./configure --with-ssl --enable-dirty-schedulers; else ./configure --with-ssl --enable-dirty-schedulers; fi'
RUN make -j$(getconf _NPROCESSORS_ONLN)
RUN make install
RUN find /usr/local -regex '/usr/local/lib/erlang/\(lib/\|erts-\).*/\(man\|doc\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf
RUN find /usr/local -name src | xargs -r find | grep -v '\.hrl$' | xargs rm -v || true
RUN find /usr/local -name src | xargs -r find | xargs rmdir -vp || true
RUN scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /usr/local | xargs -r strip --strip-all
RUN scanelf --nobanner -E ET_DYN -BF '%F' --recursive /usr/local | xargs -r strip --strip-unneeded

FROM ubuntu:${OS_VERSION} AS final

ARG ERLANG

RUN apt-get update && \
  apt-get -y --no-install-recommends install \
    libodbc1 \
    libssl1.1 \
    libsctp1

COPY --from=build /usr/local /usr/local
ENV LANG=C.UTF-8

