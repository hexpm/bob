ARG OS_VERSION

FROM debian:${OS_VERSION} AS build

ARG ERLANG

RUN apt-get update
RUN apt-get -y --no-install-recommends install \
  autoconf \
  dpkg-dev \
  gcc \
  g++ \
  make \
  libncurses-dev \
  unixodbc-dev \
  $(bash -c 'if [ "${ERLANG:0:1}" = "1" ]; then echo "libssl1.0-dev"; else echo "libssl-dev"; fi') \
  libsctp-dev \
  wget \
  ca-certificates \
  pax-utils

RUN mkdir -p /OTP/subdir
RUN wget -nv "https://github.com/erlang/otp/archive/OTP-${ERLANG}.tar.gz" && tar -zxf "OTP-${ERLANG}.tar.gz" -C /OTP/subdir --strip-components=1
WORKDIR /OTP/subdir
RUN ./otp_build autoconf

ARG PIE_CFLAGS
ARG CFLAGS="-g -O2 -fstack-protector ${PIE_CFLAGS}"
ARG CPPFLAGS="-D_FORTIFY_SOURCE=2"

ARG PIE_LDFLAGS
ARG LDFLAGS="-Wl,-z,relro,-z,now ${PIE_LDFLAGS}"

RUN ./configure --with-ssl --enable-dirty-schedulers
RUN make -j$(getconf _NPROCESSORS_ONLN)
RUN make install
RUN bash -c 'if [ "${ERLANG:0:2}" -ge "23" ]; then make docs DOC_TARGETS=chunks; else true; fi'
RUN bash -c 'if [ "${ERLANG:0:2}" -ge "23" ]; then make install-docs DOC_TARGETS=chunks; else true; fi'
RUN find /usr/local -regex '/usr/local/lib/erlang/\(lib/\|erts-\).*/\(man\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf
RUN find /usr/local -name src | xargs -r find | grep -v '\.hrl$' | xargs rm -v || true
RUN find /usr/local -name src | xargs -r find | xargs rmdir -vp || true
RUN scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /usr/local | xargs -r strip --strip-all
RUN scanelf --nobanner -E ET_DYN -BF '%F' --recursive /usr/local | xargs -r strip --strip-unneeded

FROM debian:${OS_VERSION} AS final

ARG ERLANG

RUN apt-get update && \
  apt-get -y --no-install-recommends install \
    libodbc1 \
    $(bash -c 'if [ "${ERLANG:0:1}" = "1" ]; then echo "libssl1.0.2"; else echo "libssl1.1"; fi') \
    libsctp1

COPY --from=build /usr/local /usr/local
ENV LANG=C.UTF-8
