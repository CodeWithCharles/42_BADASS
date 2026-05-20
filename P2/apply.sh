#!/bin/bash

MODE=${1:-dynamic}

if [[ "$MODE" != "static" && "$MODE" != "dynamic" ]]; then
    echo "Usage: $0 [static|dynamic]"
    exit 1
fi

router_config() {
    local id=$1 peer=$((3 - id))
    echo "ip addr add 10.1.1.${id}/24 dev eth0"
    if [[ "$MODE" == "static" ]]; then
        echo "ip link add name vxlan10 type vxlan id 10 dev eth0 local 10.1.1.${id} remote 10.1.1.${peer} dstport 4789"
    else
        echo "ip link add name vxlan10 type vxlan id 10 dev eth0 group 239.1.1.1 dstport 4789"
    fi
    echo "ip link set dev vxlan10 up"
    echo "ip link add br0 type bridge"
    echo "ip link set dev br0 up"
    echo "brctl addif br0 eth1"
    echo "brctl addif br0 vxlan10"
}

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
    id="${hostname##*-}"
    case "$hostname" in
        router_*-*)
            router_config "$id" | docker exec -i "$cid" sh
            echo "[$MODE] Router config applied to $cid ($hostname)"
            ;;
        host_*-*)
            host_config "$id" | docker exec -i "$cid" sh
            echo "Host config applied to $cid ($hostname)"
            ;;
        *)
            echo "Skipping $cid ($hostname)"
            ;;
    esac
done
