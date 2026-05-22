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
    local dc=$1
    local id=$2
    local lo_ip="1.1.1.$id"
    if [[ $dc == '1' ]]; then
        local asn=65001
    else
        local asn=65002
    fi
    cat << SHELL
ip addr add $lo_ip/32 dev lo
ip addr add 10.$dc.$id.0/31 dev eth0
ip addr add 10.$dc.$id.2/31 dev eth1
ip addr add 10.$dc.$id.4/31 dev eth2
ip link set eth0 up
ip link set eth1 up
ip link set eth2 up
vtysh << EOF
configure terminal
no ipv6 forwarding
interface lo
 ip ospf area 0
interface eth0
 ip ospf network point-to-point
 ip ospf area 0
interface eth1
 ip ospf network point-to-point
 ip ospf area 0
interface eth2
 ip ospf network point-to-point
 ip ospf area 0
router bgp $asn
 neighbor LEAF peer-group
 neighbor LEAF remote-as $asn
 neighbor LEAF update-source lo
 bgp listen range 1.1.1.0/24 peer-group LEAF
 address-family l2vpn evpn
  neighbor LEAF activate
  neighbor LEAF route-reflector-client
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
    local dc=$2
    if [[ $dc == '1' ]]; then
        local eth_ip=$(( (id - 5) * 2 + 1 ))
        local eth0_ip="10.$dc.1.$eth_ip/31"
        local eth1_ip="10.$dc.2.$eth_ip/31"
        local n1="1.1.1.1"; local n2="1.1.1.2"
        local asn=65001
    else
        local eth_ip=$(( (id - 11) * 2 + 1 ))
        local eth0_ip="10.$dc.8.$eth_ip/31"
        local eth1_ip="10.$dc.9.$eth_ip/31"
        local n1="1.1.1.8"; local n2="1.1.1.9"
        local asn=65002
    fi
    local lo_ip="1.1.1.${id}"

    # Note: the inner EOF is the vtysh heredoc delimiter, not a shell heredoc
    # delimiter — the outer heredoc uses SHELL as its marker, so EOF is literal.
    cat << SHELL
ip addr add $lo_ip/32 dev lo
ip addr add $eth0_ip dev eth0
ip addr add $eth1_ip dev eth1
ip link set eth0 up
ip link set eth1 up
ip link add tenant1 type vrf table 1100
ip link set tenant1 up
ip link add vxlan999 type vxlan id 10999 local $lo_ip dstport 4789 nolearning
ip link add br999 type bridge
ip link set vxlan999 master br999
ip link set br999 master tenant1
ip link set vxlan999 up
ip link set br999 up
ip link add vxlan100 type vxlan id 10${dc}00 local $lo_ip dstport 4789 nolearning
ip link add br100 type bridge
ip link set vxlan100 master br100
ip link set br100 master tenant1
ip link set vxlan100 up
ip link set br100 up
ip link set dev br100 address 00:00:5e:00:01:01
ip addr add 10.0.$dc.1/24 dev br100 
bridge link set dev vxlan100 neigh_suppress on
ip link set eth2 master br100 
ip link set eth2 up
vtysh << EOF
configure terminal
no ipv6 forwarding
interface eth0
 ip ospf network point-to-point
 ip ospf area 0
exit
interface eth1
 ip ospf network point-to-point
 ip ospf area 0
exit
interface lo
 ip ospf area 0
exit
vrf tenant1
 vni 10999
exit-vrf
router bgp $asn
 neighbor $n1 remote-as $asn
 neighbor $n1 update-source lo
 neighbor $n2 remote-as $asn
 neighbor $n2 update-source lo
 address-family l2vpn evpn
  neighbor $n1 activate
  neighbor $n2 activate
  advertise-all-vni
 exit-address-family
exit
router bgp $asn vrf tenant1
 address-family ipv4 unicast
  redistribute connected
 exit-address-family
exit
router ospf
exit
EOF
SHELL
}

leaf_dci_config() {
    local id=$1
    local dc=$2
    if [[ $dc == '1' ]]; then
        local eth_ip=$(( (id - 5) * 2 + 1 ))
        local eth0_ip="10.$dc.1.$eth_ip/31"
        local eth1_ip="10.$dc.2.$eth_ip/31"
        local n1="1.1.1.1"; local n2="1.1.1.2"
        local asn=65001
        local dci_ip="172.16.0.1/30"; local dci_peer="172.16.0.2"; local asn_remote=65002
    else
        local eth_ip=$(( (id - 11) * 2 + 1 ))
        local eth0_ip="10.$dc.8.$eth_ip/31"
        local eth1_ip="10.$dc.9.$eth_ip/31"
        local n1="1.1.1.8"; local n2="1.1.1.9"
        local asn=65002
        local dci_ip="172.16.0.2/30"; local dci_peer="172.16.0.1"; local asn_remote=65001
    fi
    local lo_ip="1.1.1.${id}"

    cat << SHELL
ip addr add $lo_ip/32 dev lo
ip addr add $eth0_ip dev eth0
ip addr add $eth1_ip dev eth1
ip link set eth0 up
ip link set eth1 up
ip link add tenant1 type vrf table 1100
ip link set tenant1 up
ip addr add $dci_ip dev eth2
ip link set eth2 master tenant1
ip link set eth2 up
ip link add vxlan999 type vxlan id 10999 local $lo_ip dstport 4789 nolearning
ip link add br999 type bridge
ip link set vxlan999 master br999
ip link set br999 master tenant1
ip link set vxlan999 up
ip link set br999 up
ip link add vxlan100 type vxlan id 10${dc}00 local $lo_ip dstport 4789 nolearning
ip link add br100 type bridge
ip link set vxlan100 master br100
ip link set br100 master tenant1
ip link set vxlan100 up
ip link set br100 up
ip addr add 10.0.$dc.254/24 dev br100
bridge link set dev vxlan100 neigh_suppress on
vtysh << EOF
configure terminal
no ipv6 forwarding
vrf tenant1
 vni 10999
exit-vrf
interface eth0
 ip ospf network point-to-point
 ip ospf area 0
exit
interface eth1
 ip ospf network point-to-point
 ip ospf area 0
exit
interface lo
 ip ospf area 0
exit
router ospf
exit
router bgp $asn
 neighbor $n1 remote-as $asn
 neighbor $n1 update-source lo
 neighbor $n2 remote-as $asn
 neighbor $n2 update-source lo
 address-family l2vpn evpn
  neighbor $n1 activate
  neighbor $n2 activate
  advertise-all-vni
 exit-address-family
exit
router bgp $asn vrf tenant1
 neighbor $dci_peer remote-as $asn_remote
 address-family ipv4 unicast
  redistribute connected
  neighbor $dci_peer activate
 exit-address-family
 address-family l2vpn evpn
  advertise ipv4 unicast
 exit-address-family
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
    local dc=$2
    echo "ip addr add 10.0.$dc.${id}/24 dev eth0"
    echo "ip link set eth0 up"
    echo "ip route add default via 10.0.$dc.1"
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

    # Extract the numeric ID from the GNS3 hostname suffix (e.g. "router-ale-boud-3" → "3")
    id="${hostname##*-}"

    case "$hostname" in
        router-*-1 | router-*-2)
            spine_config 1 "$id" | docker exec -i "$cid" sh
            echo "Spine DC1 config applied to $cid ($hostname id: $id)"
            ;;
        router-*-8 | router-*-9)
            spine_config 2 "$id" | docker exec -i "$cid" sh
            echo "Spine DC2 config applied to $cid ($hostname id: $id)"
            ;;
        router-*-5 | router-*-6)
            leaf_config "$id" 1 | docker exec -i "$cid" sh
            echo "Leaf config applied to $cid ($hostname id: $id)"
            ;;
        router-*-12 | router-*-13)
            leaf_config "$id" 2 | docker exec -i "$cid" sh
            echo "Leaf config applied to $cid ($hostname id: $id)"
            ;;
        router-*-7)
            leaf_dci_config "$id" 1 | docker exec -i "$cid" sh
            echo "Leaf config applied to $cid ($hostname id: $id)"
            ;;
        router-*-11)
            leaf_dci_config "$id" 2 | docker exec -i "$cid" sh
            echo "Leaf config applied to $cid ($hostname id: $id)"
            ;;
        host-*-2 | host-*-3)
            host_config "$id" 1 | docker exec -i "$cid" sh
            echo "Host config applied to $cid ($hostname id: $id)"
            ;;
        host-*-5 | host-*-4)
            host_config "$id" 2 | docker exec -i "$cid" sh
            echo "Host config applied to $cid ($hostname id: $id)"
            ;;
        *)
            # Not a managed container (e.g. unrelated service)
            echo "Skipping $cid ($hostname)"
            ;;
    esac
done
