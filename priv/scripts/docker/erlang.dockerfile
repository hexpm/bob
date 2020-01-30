ARG ALPINE

FROM alpine:${ALPINE} AS build

ARG ERLANG

RUN apk add --no-cache --update wget tar binutils
RUN wget -q -O /tmp/otp.tar.gz https://repo.hex.pm/builds/otp/alpine-3.10/OTP-${ERLANG}.tar.gz
RUN mkdir /otp
RUN tar zxf /tmp/otp.tar.gz -C /otp --strip-components=1
RUN /otp/Install -minimal /otp
RUN find /otp -regex '/otp/lib/erlang/\(lib/\|erts-\).*/\(man\|doc\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf
RUN find /otp -name src | xargs -r find | grep -v '\.hrl$' | xargs rm -v || true
RUN find /otp -name src | xargs -r find | xargs rmdir -vp || true
RUN scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /otp | xargs -r strip --strip-all
RUN scanelf --nobanner -E ET_DYN -BF '%F' --recursive /otp | xargs -r strip --strip-unneeded

FROM alpine:${ALPINE} AS final

RUN apk add --update --no-cache \
    ncurses

RUN mkdir /otp
COPY --from=build /otp /otp
ENV PATH=/otp/bin:$PATH
