ARG OS_VERSION

FROM ubuntu:${OS_VERSION} AS build

ARG ERLANG

RUN apt-get update
RUN apt-get -y install wget pax-utils binutils
RUN wget -q -O /tmp/otp.tar.gz https://repo.hex.pm/builds/otp/ubuntu-14.04/OTP-${ERLANG}.tar.gz
RUN mkdir /otp
RUN tar zxf /tmp/otp.tar.gz -C /otp --strip-components=1
RUN /otp/Install -minimal /otp
RUN find /otp -regex '/otp/lib/erlang/\(lib/\|erts-\).*/\(man\|doc\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf
RUN find /otp -name src | xargs -r find | grep -v '\.hrl$' | xargs rm -v || true
RUN find /otp -name src | xargs -r find | xargs rmdir -vp || true
RUN scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /otp | xargs -r strip --strip-all
RUN scanelf --nobanner -E ET_DYN -BF '%F' --recursive /otp | xargs -r strip --strip-unneeded

FROM ubuntu:${OS_VERSION} AS final

RUN mkdir /otp
COPY --from=build /otp /otp
ENV PATH=/otp/bin:$PATH LANG=C.UTF-8

