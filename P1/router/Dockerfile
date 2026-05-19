# Base image: FRRouting - provides zebra, bgpd, ospfd, isisd out of the box
FROM frrouting/frr:latest

# busybox-extras: required by the subject, provides shell utilities
# iputils: ping and other network tools
RUN apk update && apk add --no-cache \
    busybox-extras \
    iputils

# Enable the required daemons in FRR's daemon config file:
# - bgpd:  BGP daemon (Border Gateway Protocol)
# - ospfd: OSPF daemon (Open Shortest Path First interior routing)
# - isisd: IS-IS routing engine (required by subject)
RUN sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons && \
    sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons && \
    sed -i 's/isisd=no/isisd=yes/' /etc/frr/daemons

# tini is used as init process, docker-start launches all FRR daemons
CMD ["/sbin/tini", "--", "/usr/lib/frr/docker-start"]