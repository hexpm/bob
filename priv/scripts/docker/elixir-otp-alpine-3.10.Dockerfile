FROM alpine:3.10 as build

ARG otp

RUN apk add --update wget tar
RUN wget -q -O /tmp/otp.tar.gz https://repo.hex.pm/builds/otp/alpine-3.10/${otp}.tar.gz
RUN mkdir /otp
RUN tar zxf /tmp/otp.tar.gz -C /otp --strip-components=1
RUN /otp/Install -minimal /otp

FROM alpine:3.10 AS final

RUN apk add --update openssl
RUN mkdir /otp
COPY --from=build /otp /otp
ENV PATH=/otp/bin:$PATH
