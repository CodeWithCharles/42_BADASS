#!/bin/bash
# Applies VXLAN network configuration to all running GNS3 Docker containers.
# Usage: ./apply.sh [static|dynamic]   (defaults to dynamic)
#
# static  — unicast VXLAN: each router explicitly knows its peer's IP
# dynamic — multicast VXLAN: routers discover peers via group 239.1.1.1

MODE=${1:-dynamic}

if [[ "$MODE" != "static" && "$MODE" != "dynamic" ]]; then
    echo "Usage: $0 [static|dynamic]"
    exit 1
fi

# Prints the shell commands that configure a router container.
# The output is piped directly into the container's shell — no file copy needed.
# $1: router ID (e.g. 1 or 2)
# Uses global $MODE to decide between static (unicast) and dynamic (multicast).
router_config() {
    local id=$1
    # For a 2-router setup, peer is always the other one: 1↔2
    local peer=$((3 - id))

    # Assign the router's IP on the eth0 backbone link
    echo "ip addr add 10.1.1.${id}/24 dev eth0"

    if [[ "$MODE" == "static" ]]; then
        # Unicast VXLAN: tunnel goes directly to the known peer IP
        echo "ip link add name vxlan10 type vxlan id 10 dev eth0 local 10.1.1.${id} remote 10.1.1.${peer} dstport 4789"
    else
        # Multicast VXLAN: routers join a group and discover each other dynamically
        echo "ip link add name vxlan10 type vxlan id 10 dev eth0 group 239.1.1.1 dstport 4789"
    fi

    echo "ip link set dev vxlan10 up"

    # Bridge eth1 (LAN side) and vxlan10 (overlay tunnel) together
    # so hosts on both sides share the same L2 segment across the VXLAN
    echo "ip link add br0 type bridge"
    echo "ip link set dev br0 up"
    echo "brctl addif br0 eth1"
    echo "brctl addif br0 vxlan10"
}

# Prints the shell commands that configure a host container.
# Hosts only need an IP on eth1 — no VXLAN or bridging required.
# $1: host ID (e.g. 1 or 2)
host_config() {
    local id=$1
    echo "ip addr add 30.1.1.${id}/24 dev eth1"
}

running=$(docker ps -q)
if [[ -z "$running" ]]; then
    echo "No running containers"
    exit 1
fi

for cid in $running; do
    hostname=$(docker exec "$cid" hostname)

    # Extract the numeric ID from the GNS3 hostname suffix (e.g. "router_sucho-1" → "1")
    id="${hostname##*-}"

    case "$hostname" in
        router_*-*)
            # Generate config inline and pipe it into the container — avoids docker cp
            router_config "$id" | docker exec -i "$cid" sh
            echo "[$MODE] Router config applied to $cid ($hostname)"
            ;;
        host_*-*)
            host_config "$id" | docker exec -i "$cid" sh
            echo "Host config applied to $cid ($hostname)"
            ;;
        *)
            # Not a managed container (e.g. a leftover or unrelated service)
            echo "Skipping $cid ($hostname)"
            ;;
    esac
done
