#!/usr/bin/env bash
# EX1, topology C (bridge + VXLAN), corrected setup and test.
#
# Usage (run as root, from the folder where you want the result files):
#   sudo bash vxlan_fix.sh setup      # build the corrected topology
#   sudo bash vxlan_fix.sh test       # ping + iperf3 TCP + iperf3 UDP, results saved to files
#   sudo bash vxlan_fix.sh cleanup    # remove everything created here (old faulty setup too)
#
# Needs: ns1 and ns2 already exist (from the docker containers), iproute2, iperf3, ping.
# Optional: DUR=60 sudo -E bash vxlan_fix.sh test   (TCP duration in seconds, default 10)
#
# Path of a packet from ns1 to ns2:
#   ns1 vx-veth0 -> vx-veth0-br -> bridge vx-net-0 -> vxlan1 =(UDP 4789 over vx-under0/1)=> vxlan2
#   -> bridge vx-net-1 (in host2) -> vx-veth1-br -> vx-veth1 ns2

set -u
DUR=${DUR:-10}

cleanup() {
  # Old faulty setup and the corrected one; errors are ignored when something does not exist.
  ip link del vx-veth0-br 2>/dev/null    # also removes its peer vx-veth0 in ns1
  ip link del vx-veth1-br 2>/dev/null    # old setup: also removes vx-veth1 in ns2
  ip link del vx-veth0-mid 2>/dev/null   # old setup: also removes vx-veth1-mid
  ip link del vxlan1 2>/dev/null
  ip link del vxlan2 2>/dev/null
  ip link del vx-net-0 2>/dev/null
  ip link del vx-net-1 2>/dev/null
  ip link del vx-under0 2>/dev/null      # new setup: also removes vx-under1 in host2
  ip netns del host2 2>/dev/null         # removes everything inside host2 as well
  echo "cleanup done"
}

setup() {
  cleanup

  # 1. A second "host" namespace, so the VXLAN underlay is a real routed link
  ip netns add host2
  ip netns exec host2 ip link set lo up

  # 2. Underlay veth pair between the root namespace and host2.
  #    MTU 1600 leaves room for the 50-byte VXLAN header, so ns1/ns2 keep MTU 1500
  #    like in the other tests and the results stay comparable.
  ip link add vx-under0 type veth peer name vx-under1 netns host2
  ip link set vx-under0 mtu 1600
  ip netns exec host2 ip link set vx-under1 mtu 1600
  ip addr add 10.10.10.1/24 dev vx-under0
  ip netns exec host2 ip addr add 10.10.10.2/24 dev vx-under1
  ip link set vx-under0 up
  ip netns exec host2 ip link set vx-under1 up

  # 3. VXLAN endpoints: same VNI (100) and same port (4789) on both sides
  ip link add vxlan1 type vxlan id 100 local 10.10.10.1 remote 10.10.10.2 dstport 4789 dev vx-under0
  ip netns exec host2 ip link add vxlan2 type vxlan id 100 local 10.10.10.2 remote 10.10.10.1 dstport 4789 dev vx-under1
  ip link set vxlan1 mtu 1500
  ip netns exec host2 ip link set vxlan2 mtu 1500

  # 4. One bridge on each side, each with its VXLAN interface
  ip link add vx-net-0 type bridge
  ip netns exec host2 ip link add vx-net-1 type bridge
  ip link set vxlan1 master vx-net-0
  ip netns exec host2 ip link set vxlan2 master vx-net-1

  # 5. veth pairs from ns1 and ns2 to their bridge
  ip link add vx-veth0 netns ns1 type veth peer name vx-veth0-br
  ip link add vx-veth1 netns ns2 type veth peer name vx-veth1-br netns host2
  ip link set vx-veth0-br master vx-net-0
  ip netns exec host2 ip link set vx-veth1-br master vx-net-1

  # 6. Addresses inside ns1 and ns2
  ip netns exec ns1 ip addr add 192.168.60.1/24 dev vx-veth0
  ip netns exec ns2 ip addr add 192.168.60.2/24 dev vx-veth1

  # 7. Bring everything up
  ip link set vxlan1 up
  ip link set vx-veth0-br up
  ip link set vx-net-0 up
  ip netns exec host2 ip link set vxlan2 up
  ip netns exec host2 ip link set vx-veth1-br up
  ip netns exec host2 ip link set vx-net-1 up
  ip netns exec ns1 ip link set lo up
  ip netns exec ns1 ip link set vx-veth0 up
  ip netns exec ns2 ip link set lo up
  ip netns exec ns2 ip link set vx-veth1 up

  echo "setup done; checking connectivity"
  ip netns exec ns1 ping -c 3 192.168.60.2
}

run_test() {
  ip netns exec ns2 iperf3 -s -D -I /tmp/iperf3_vxlan.pid
  sleep 1

  echo "== latency (ping, 100 packets) =="
  ip netns exec ns1 ping -c 100 -i 0.2 -q 192.168.60.2 | tee ping_vxlan_fixed.txt

  echo "== TCP, ${DUR} s =="
  ip netns exec ns1 iperf3 -c 192.168.60.2 -t "$DUR" | tee iperf3_tunnel_fixed.txt

  echo "== UDP 100 Mbit/s, 60 s =="
  ip netns exec ns1 iperf3 -c 192.168.60.2 -u -b 100M -t 60 | tee udp_vxlan_fixed.txt

  echo "== proof that traffic used the tunnel: vxlan1 counters should be in the GB range =="
  ip -s link show vxlan1 | tee vxlan1_counters.txt

  kill "$(cat /tmp/iperf3_vxlan.pid)" 2>/dev/null
}

case "${1:-}" in
  setup)   setup ;;
  test)    run_test ;;
  cleanup) cleanup ;;
  *) echo "usage: sudo bash $0 setup|test|cleanup"; exit 1 ;;
esac
