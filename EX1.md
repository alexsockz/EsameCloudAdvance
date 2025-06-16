ns1            ns2
 veth0 ---- veth1

sudo ip netns add ns1
sudo ip netns add ns2

ip netns list
-    ns1
-    ns2


connetto direttamente con veth:
(veth0 in ns1 connected to veth1 in ns2)

sudo ip link add veth0 netns ns1 type veth peer veth1 netns ns2

sudo ip netns exec ns1 ip link

    1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN mode DEFAULT group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    2: veth0@if2: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
        link/ether 36:be:08:32:11:e4 brd ff:ff:ff:ff:ff:ff link-netns ns2
    --- notare che è DOWN, devo aggiungere ip alla veth0 rendo up sia veth0 che l0

sudo ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth0
sudo ip netns exec ns1 ip link set veth0 up
sudo ip netns exec ns1 ip link set lo up

sudo ip netns exec ns1 ip link

    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    2: veth0@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
        link/ether 36:be:08:32:11:e4 brd ff:ff:ff:ff:ff:ff link-netns ns2

faccio stessa cosa per ns2:

sudo ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth1
sudo ip netns exec ns2 ip link set veth1 up
sudo ip netns exec ns2 ip link set lo up

sudo ip netns exec ns2 ip link

    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    2: veth1@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
        link/ether 82:2e:92:46:af:48 brd ff:ff:ff:ff:ff:ff link-netns ns1


provo a pingare:

sudo ip netns exec ns1 ping 10.0.0.2

sudo ip netns exec ns1 ip route
sudo ip netns exec ns1 ip neigh

    10.0.0.0/24 dev veth0 proto kernel scope link src 10.0.0.1 
    10.0.0.2 dev veth0 lladdr 82:2e:92:46:af:48 STALE

setto ns2 come server:
sudo ip netns exec ns2 iperf3 -s

setto ns1 come client:
sudo ip netns exec ns1 iperf3 -c 10.0.0.2 | tee iperf3.txt


ip netns add dev
ip netns add prod


----------------------------------------------------------------------------
                     v-net-0
          b-veth0-br ------- b-veth1-br
ns1      /                             \      ns2
  b-veth0                               b-veth1

creo bridge

sudo ip link add v-net-0 type bridge
sudo ip link set dev v-net-0 up

brctl show 

    bridge name	bridge id		STP enabled	interfaces
    v-net-0		8000.96304db0a79a	no

sudo ip link add b-veth0 type veth peer name b-veth0-br

sudo ip link add b-veth1 type veth peer name b-veth1-br

sudo ip link set b-veth0 netns ns1
sudo ip link set b-veth0-br master v-net-0

sudo ip link set b-veth1 netns ns2
sudo ip link set b-veth1-br master v-net-0

sudo ip netns exec ns1 ip addr add 192.168.10.1/24 dev b-veth0
sudo ip netns exec ns2 ip addr add 192.168.10.2/24 dev b-veth1

sudo ip netns exec ns1 ip link set b-veth0 up
sudo ip netns exec ns2 ip link set b-veth1 up
sudo ip link set b-veth0-br up
sudo ip link set b-veth1-br up

sudo ip netns exec ns1 ping 192.168.10.2

sudo ip netns exec ns1 iperf3 -c 192.168.10.2 | tee iperf3_bridge.txt


----------------------------------------------------------------------------


####  NON VA
                       vx-net-0             vxlan-tunnel             vx-net-1
           vx-veth0-br -------- vx-veth0-mid ========== vx-veth1-mid -------- vx-veth1-br
ns1       /                                                                             \      ns2
  vx-veth0                                                                               vx-veth1  

sudo ip netns add ns1
sudo ip netns add ns2

sudo ip link add vx-net-0 type bridge
sudo ip link add vx-net-1 type bridge


sudo ip link add vx-veth0 type veth peer name vx-veth0-br
sudo ip link add vx-veth1 type veth peer name vx-veth1-br


sudo ip link set vx-veth0 netns ns1
sudo ip link set vx-veth0-br master vx-net-0

sudo ip link set vx-veth1 netns ns2
sudo ip link set vx-veth1-br master vx-net-1


sudo ip netns exec ns1 ip addr add 192.168.60.1/24 dev vx-veth0
sudo ip netns exec ns2 ip addr add 192.168.60.2/24 dev vx-veth1

sudo ip addr add 192.168.60.3/24 dev vx-veth0-br
sudo ip addr add 192.168.60.4/24 dev vx-veth1-br

sudo ip link add vxlan0 type vxlan id 43 dev vx-veth0-br remote 192.168.60.4 dstport 4789
sudo ip link add vxlan1 type vxlan id 43 dev vx-veth1-br remote 192.168.60.3 dstport 4789

sudo ip netns exec ns1 ip link set vx-veth0 address aa:aa:aa:aa:aa:01
sudo ip netns exec ns2 ip link set vx-veth1 address aa:aa:aa:aa:aa:02

sudo bridge fdb add aa:aa:aa:aa:aa:02 dev vxlan0 dst 192.168.60.4
sudo bridge fdb add aa:aa:aa:aa:aa:01 dev vxlan1 dst 192.168.60.3

sudo ip link set vxlan0 master vx-net-0
sudo ip link set vxlan1 master vx-net-1


sudo ip netns exec ns1 ip link set lo up
sudo ip netns exec ns2 ip link set lo up
sudo ip link set vx-net-0 up
sudo ip link set vx-net-1 up
sudo ip netns exec ns1 ip link set vx-veth0 up
sudo ip netns exec ns2 ip link set vx-veth1 up
sudo ip link set vxlan0 up
sudo ip link set vxlan1 up
sudo ip link set vx-veth0-br up
sudo ip link set vx-veth1-br up



sudo ip netns del ns1
sudo ip netns del ns2
sudo ip link del vx-veth0-br
sudo ip link del vx-veth1-br
sudo ip link del vx-net-0
sudo ip link del vx-net-1
sudo ip link del vxlan0
sudo ip link del vxlan1