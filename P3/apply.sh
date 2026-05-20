#!/bin/bash
# Applies BGP EVPN / VXLAN configuration to all running GNS3 Docker containers.
# Usage: ./apply.sh
#
# Roles:
#   router_*-1        — spine / BGP route reflector (vtysh only, no VXLAN)
#   router_*-{2,3,4}  — leaf  / VTEP (VXLAN + bridge + vtysh)
#   host_*-{1,2,3}    — end host (single IP on eth0)

# --------------------------------------------------------------------------
# Spine config (router-1)
# Hardcoded: three /30 point-to-point links to the three leaves, loopback,
# BGP dynamic-neighbor route reflector for EVPN, OSPF on all interfaces.
# --------------------------------------------------------------------------
spine_config() {
    cat << 'SHELL'
vtysh << EOF
configure terminal
no ipv6 forwarding
interface eth0
 ip address 10.1.1.1/30
exit
interface eth1
 ip address 10.1.1.5/30
exit
interface eth2
 ip address 10.1.1.9/30
exit
interface lo
 ip address 1.1.1.1/32
exit
router bgp 1
 neighbor DYNAMIC peer-group
 neighbor DYNAMIC remote-as 1
 neighbor DYNAMIC update-source lo
 bgp listen range 1.1.1.0/24 peer-group DYNAMIC
 address-family l2vpn evpn
  neighbor DYNAMIC activate
  neighbor DYNAMIC route-reflector-client
 exit-address-family
exit
router ospf
 network 0.0.0.0/0 area 0
exit
EOF
SHELL
}

# --------------------------------------------------------------------------
# Leaf config (routers 2–4)
# Parameterized by router ID:
#   eth0 IP : 10.1.1.((id-2)*4+2)/30  →  R2=10.1.1.2  R3=10.1.1.6  R4=10.1.1.10
#   lo  IP  : 1.1.1.id/32
#   eth0     = uplink to spine  (OSPF + VXLAN base device)
#   eth1     = host-facing port (bridged into the overlay)
# --------------------------------------------------------------------------
leaf_config() {
    local id=$1
    local eth0_ip="10.1.1.$(( (id - 2) * 4 + 2 ))/30"
    local lo_ip="1.1.1.${id}/32"

    # Note: the inner EOF is the vtysh heredoc delimiter, not a shell heredoc
    # delimiter — the outer heredoc uses SHELL as its marker, so EOF is literal.
    cat << SHELL
ip link add name vxlan10 type vxlan id 10 dev eth0 dstport 4789
ip link set dev vxlan10 up
ip link add name br0 type bridge
ip link set dev br0 up
brctl addif br0 eth1
brctl addif br0 vxlan10
vtysh << EOF
configure terminal
no ipv6 forwarding
interface eth0
 ip address ${eth0_ip}
 ip ospf area 0
exit
interface lo
 ip address ${lo_ip}
 ip ospf area 0
exit
router bgp 1
 neighbor 1.1.1.1 remote-as 1
 neighbor 1.1.1.1 update-source lo
 address-family l2vpn evpn
  neighbor 1.1.1.1 activate
  advertise-all-vni
 exit-address-family
exit
router ospf
exit
EOF
SHELL
}

# --------------------------------------------------------------------------
# Host config
# Hosts only need a single IP on eth0 — no routing or tunneling required.
# --------------------------------------------------------------------------
host_config() {
    local id=$1
    echo "ip addr add 20.1.1.${id}/24 dev eth0"
}

# --------------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------------
running=$(docker ps -q)
if [[ -z "$running" ]]; then
    echo "No running containers"
    exit 1
fi

for cid in $running; do
    hostname=$(docker exec "$cid" hostname)

    # Extract the numeric ID from the GNS3 hostname suffix (e.g. "router_cpoulain-3" → "3")
    id="${hostname##*-}"

    case "$hostname" in
        router-*-1)
            spine_config | docker exec -i "$cid" sh
            echo "Spine config applied to $cid ($hostname)"
            ;;
        router-*-*)
            leaf_config "$id" | docker exec -i "$cid" sh
            echo "Leaf config applied to $cid ($hostname)"
            ;;
        host-*-*)
            host_config "$id" | docker exec -i "$cid" sh
            echo "Host config applied to $cid ($hostname)"
            ;;
        *)
            # Not a managed container (e.g. unrelated service)
            echo "Skipping $cid ($hostname)"
            ;;
    esac
done
