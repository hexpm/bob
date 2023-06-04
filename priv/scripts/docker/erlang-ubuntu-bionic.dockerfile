ARG OS_VERSION

FROM ubuntu:${OS_VERSION} AS build

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
RUN ./configure --with-ssl --enable-dirty-schedulers
RUN make -j$(getconf _NPROCESSORS_ONLN)
RUN make -j$(getconf _NPROCESSORS_ONLN) install
RUN bash -c 'if [ "${ERLANG:0:2}" -ge "23" ]; then make -j$(getconf _NPROCESSORS_ONLN) docs DOC_TARGETS=chunks; else true; fi'
RUN bash -c 'if [ "${ERLANG:0:2}" -ge "23" ]; then make -j$(getconf _NPROCESSORS_ONLN) install-docs DOC_TARGETS=chunks; else true; fi'
RUN find /usr/local -regex '/usr/local/lib/erlang/\(lib/\|erts-\).*/\(man\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf
RUN find /usr/local -name src | xargs -r find | grep -v '\.hrl$' | xargs rm -v || true
RUN find /usr/local -name src | xargs -r find | xargs rmdir -vp || true
RUN scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /usr/local | xargs -r strip --strip-all
RUN scanelf --nobanner -E ET_DYN -BF '%F' --recursive /usr/local | xargs -r strip --strip-unneeded

FROM ubuntu:${OS_VERSION} AS final

ARG ERLANG

RUN apt-get update && \
  apt-get -y --no-install-recommends install \
    ca-certificates \
    libodbc1 \
    $(bash -c 'if [ "${ERLANG:0:1}" = "1" ]; then echo "libssl1.0.0"; else echo "libssl1.1"; fi') \
    libsctp1 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local /usr/local
ENV LANG=C.UTF-8
