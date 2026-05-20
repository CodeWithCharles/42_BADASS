# Base image: Alpine Linux - lightweight and perfect for a simple host
FROM alpine:latest

# busybox-extras: provides networking tools (ping, telnet, etc.)
# iputils: additional network utilities
RUN apk update && apk add --no-cache \
    busybox-extras \
    iputils \
    tcpdump \
    vim

# Default shell - GNS3 will connect via telnet to this
CMD ["/bin/sh"]