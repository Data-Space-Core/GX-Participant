FROM alpine:3.20

RUN apk add --no-cache bash coreutils kubectl openssl xxd

COPY entrypoint.sh /usr/local/bin/gx-participant-bootstrap
RUN chmod +x /usr/local/bin/gx-participant-bootstrap

ENTRYPOINT ["/usr/local/bin/gx-participant-bootstrap"]
