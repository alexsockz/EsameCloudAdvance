#!/usr/bin/env bash
# EX1: build, test and tear down the three namespace topologies, one after the other.
#
#   sudo bash ex1_netns.sh              # all three: veth, bridge, vxlan
#   sudo bash ex1_netns.sh vxlan        # a single one: veth | bridge | vxlan
#   sudo bash ex1_netns.sh cleanup      # remove everything this script can create
#
# Options (environment variables; pass them with sudo -E, e.g. RUNS=5 DUR=60 sudo -E bash ex1_netns.sh):
#   DUR=10      TCP test duration in seconds per run
#   RUNS=1      number of TCP runs per topology (use 5 or more for mean and standard deviation)
#   UDP_DUR=60  UDP test duration in seconds (0 skips the UDP test)
#   KEEP=1      do not tear down the last topology tested (to inspect it by hand)
#
# Results go to ./results/: <topology>_ping.txt, <topology>_tcp_run<N>.txt, <topology>_udp.txt,
# plus vxlan_counters.txt. Needs iproute2 (ip), iperf3 and ping. The namespaces are plain
# "ip netns add" namespaces; no Docker is involved.
#
# Topologies (addresses are the same as in the earlier manual tests):
#   veth   : ns1 veth0 ---- veth1 ns2                                   10.0.0.1  <-> 10.0.0.2
#   bridge : ns1 b-veth0 -- bridge v-net-0 -- b-veth1 ns2              192.168.10.1 <-> 192.168.10.2
#   vxlan  : ns1 -- bridge vx-net-0 -- vxlan1 ==UDP 4789== vxlan2 -- bridge vx-net-1 -- ns2
#            (the second bridge lives in namespace host2, so the underlay link vx-under0/1
#             between the two "hosts" is real; 192.168.60.1 <-> 192.168.60.2)

set -u
DUR=${DUR:-10}
RUNS=${RUNS:-1}
UDP_DUR=${UDP_DUR:-60}
KEEP=${KEEP:-0}
OUT=results
PIDFILE=/tmp/ex1_iperf3.pid
TARGET=""

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0 [all|veth|bridge|vxlan|cleanup]"; exit 1; }
for tool in ip iperf3 ping; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool"; exit 1; }
done

stop_server() {
  [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
  rm -f "$PIDFILE"
}

cleanup() {
  stop_server
  # Devices that live in the root namespace (bridges, vxlan1, underlay end); errors ignored
  for l in vxlan1 vx-net-0 v-net-0 vx-under0; do
    ip link del "$l" 2>/dev/null
  done
  # Deleting a namespace also removes the veth ends inside it (and their peers)
  for n in ns1 ns2 host2; do
    ip netns del "$n" 2>/dev/null
  done
}

setup_veth() {
  TARGET=10.0.0.2
  ip link add veth0 netns ns1 type veth peer name veth1 netns ns2
  ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth0
  ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth1
  ip netns exec ns1 ip link set veth0 up
  ip netns exec ns2 ip link set veth1 up
}

setup_bridge() {
  TARGET=192.168.10.2
  ip link add v-net-0 type bridge
  ip link set v-net-0 up
  ip link add b-veth0 type veth peer name b-veth0-br
  ip link add b-veth1 type veth peer name b-veth1-br
  ip link set b-veth0 netns ns1
  ip link set b-veth1 netns ns2
  ip link set b-veth0-br master v-net-0
  ip link set b-veth1-br master v-net-0
  ip netns exec ns1 ip addr add 192.168.10.1/24 dev b-veth0
  ip netns exec ns2 ip addr add 192.168.10.2/24 dev b-veth1
  ip netns exec ns1 ip link set b-veth0 up
  ip netns exec ns2 ip link set b-veth1 up
  ip link set b-veth0-br up
  ip link set b-veth1-br up
}

setup_vxlan() {
  TARGET=192.168.60.2

  # A second "host" namespace, so the VXLAN underlay is a real routed link
  ip netns add host2
  ip netns exec host2 ip link set lo up

  # Underlay veth pair between the root namespace and host2.
  # MTU 1600 leaves room for the 50-byte VXLAN header, so ns1/ns2 keep MTU 1500
  # like in the other two topologies and the results stay comparable.
  ip link add vx-under0 type veth peer name vx-under1 netns host2
  ip link set vx-under0 mtu 1600
  ip netns exec host2 ip link set vx-under1 mtu 1600
  ip addr add 10.10.10.1/24 dev vx-under0
  ip netns exec host2 ip addr add 10.10.10.2/24 dev vx-under1
  ip link set vx-under0 up
  ip netns exec host2 ip link set vx-under1 up

  # VXLAN endpoints: same VNI (100) and same port (4789) on both sides
  ip link add vxlan1 type vxlan id 100 local 10.10.10.1 remote 10.10.10.2 dstport 4789 dev vx-under0
  ip netns exec host2 ip link add vxlan2 type vxlan id 100 local 10.10.10.2 remote 10.10.10.1 dstport 4789 dev vx-under1
  ip link set vxlan1 mtu 1500
  ip netns exec host2 ip link set vxlan2 mtu 1500

  # One bridge on each side, each holding its VXLAN interface
  ip link add vx-net-0 type bridge
  ip netns exec host2 ip link add vx-net-1 type bridge
  ip link set vxlan1 master vx-net-0
  ip netns exec host2 ip link set vxlan2 master vx-net-1

  # veth pairs from ns1 and ns2 to their bridge
  ip link add vx-veth0 netns ns1 type veth peer name vx-veth0-br
  ip link add vx-veth1 netns ns2 type veth peer name vx-veth1-br netns host2
  ip link set vx-veth0-br master vx-net-0
  ip netns exec host2 ip link set vx-veth1-br master vx-net-1

  # Addresses inside ns1 and ns2
  ip netns exec ns1 ip addr add 192.168.60.1/24 dev vx-veth0
  ip netns exec ns2 ip addr add 192.168.60.2/24 dev vx-veth1

  # Bring everything up
  ip link set vxlan1 up
  ip link set vx-veth0-br up
  ip link set vx-net-0 up
  ip netns exec host2 ip link set vxlan2 up
  ip netns exec host2 ip link set vx-veth1-br up
  ip netns exec host2 ip link set vx-net-1 up
  ip netns exec ns1 ip link set vx-veth0 up
  ip netns exec ns2 ip link set vx-veth1 up
}

run_topology() {
  local topo=$1
  echo
  echo "=================== $topo ==================="
  cleanup
  ip netns add ns1
  ip netns add ns2
  ip netns exec ns1 ip link set lo up
  ip netns exec ns2 ip link set lo up
  "setup_$topo"
  mkdir -p "$OUT"

  echo "-- connectivity"
  if ! ip netns exec ns1 ping -c 3 -q "$TARGET"; then
    echo "ping failed, skipping $topo"
    cleanup
    return 1
  fi

  ip netns exec ns2 iperf3 -s -D -I "$PIDFILE"
  sleep 1

  echo "-- latency (100 pings)"
  ip netns exec ns1 ping -c 100 -i 0.2 -q "$TARGET" | tee "$OUT/${topo}_ping.txt"

  for r in $(seq 1 "$RUNS"); do
    echo "-- TCP run $r of $RUNS (${DUR} s)"
    ip netns exec ns1 iperf3 -c "$TARGET" -t "$DUR" | tee "$OUT/${topo}_tcp_run${r}.txt"
  done

  if [ "$UDP_DUR" -gt 0 ]; then
    echo "-- UDP 100 Mbit/s (${UDP_DUR} s)"
    ip netns exec ns1 iperf3 -c "$TARGET" -u -b 100M -t "$UDP_DUR" | tee "$OUT/${topo}_udp.txt"
  fi

  if [ "$topo" = vxlan ]; then
    echo "-- vxlan1 counters (tens of GB here prove the traffic used the tunnel)"
    ip -s link show vxlan1 | tee "$OUT/vxlan_counters.txt"
  fi

  stop_server
}

summary() {
  echo
  echo "=================== summary ==================="
  for t in veth bridge vxlan; do
    ls "$OUT/${t}_tcp_run"*.txt >/dev/null 2>&1 || continue
    echo "[$t]"
    grep -hE "sender|receiver" "$OUT/${t}_tcp_run"*.txt
    [ -f "$OUT/${t}_udp.txt" ] && grep -h "receiver" "$OUT/${t}_udp.txt"
    grep -h "rtt" "$OUT/${t}_ping.txt"
  done
}

case "${1:-all}" in
  veth|bridge|vxlan)
    run_topology "$1"
    [ "$KEEP" = 1 ] || cleanup
    summary
    ;;
  all)
    for t in veth bridge vxlan; do
      run_topology "$t"
    done
    [ "$KEEP" = 1 ] || cleanup
    summary
    ;;
  cleanup)
    cleanup
    echo "cleanup done"
    ;;
  *)
    echo "usage: sudo bash $0 [all|veth|bridge|vxlan|cleanup]"
    exit 1
    ;;
esac
