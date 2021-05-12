ARG OS_VERSION

FROM alpine:${OS_VERSION} AS build

ARG ERLANG

RUN apk --no-cache upgrade
RUN apk add --no-cache \
  dpkg-dev \
  dpkg \
  bash \
  pcre \
  ca-certificates \
  $(if [ "${ERLANG:0:1}" = "1" ]; then echo "libressl-dev"; else echo "openssl-dev"; fi) \
  ncurses-dev \
  unixodbc-dev \
  zlib-dev \
  lksctp-tools-dev \
  autoconf \
  build-base \
  perl-dev \
  wget \
  tar \
  binutils

RUN mkdir -p /OTP/subdir
RUN wget -nv "https://github.com/erlang/otp/archive/OTP-${ERLANG}.tar.gz" && tar -zxf "OTP-${ERLANG}.tar.gz" -C /OTP/subdir --strip-components=1
WORKDIR /OTP/subdir
RUN ./otp_build autoconf

ARG PIE_CFLAGS
ARG CF_PROTECTION
ARG CFLAGS="-g -O2 -fstack-clash-protection ${CF_PROTECTION} ${PIE_CFLAGS}"

RUN ./configure \
  --build="$(dpkg-architecture --query DEB_HOST_GNU_TYPE)" \
  --without-javac \
  --without-wx \
  --without-debugger \
  --without-observer \
  --without-jinterface \
  --without-cosEvent\
  --without-cosEventDomain \
  --without-cosFileTransfer \
  --without-cosNotification \
  --without-cosProperty \
  --without-cosTime \
  --without-cosTransactions \
  --without-et \
  --without-gs \
  --without-ic \
  --without-megaco \
  --without-orber \
  --without-percept \
  --without-typer \
  --with-ssl \
  --enable-threads \
  --enable-dirty-schedulers \
  --disable-hipe
RUN make -j$(getconf _NPROCESSORS_ONLN)
RUN make install
RUN if [ "${ERLANG:0:2}" -ge "23" ]; then make docs DOC_TARGETS=chunks; else true; fi
RUN if [ "${ERLANG:0:2}" -ge "23" ]; then make install-docs DOC_TARGETS=chunks; else true; fi
RUN find /usr/local -regex '/usr/local/lib/erlang/\(lib/\|erts-\).*/\(man\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf
RUN find /usr/local -name src | xargs -r find | grep -v '\.hrl$' | xargs rm -v || true
RUN find /usr/local -name src | xargs -r find | xargs rmdir -vp || true
RUN scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /usr/local | xargs -r strip --strip-all
RUN scanelf --nobanner -E ET_DYN -BF '%F' --recursive /usr/local | xargs -r strip --strip-unneeded

FROM alpine:${OS_VERSION} AS final

ARG ERLANG

RUN apk add --update --no-cache \
  libstdc++ \
  ncurses \
  $(if [ "${ERLANG:0:1}" = "1" ]; then echo "libressl"; else echo "openssl"; fi) \
  unixodbc \
  lksctp-tools

COPY --from=build /usr/local /usr/local
