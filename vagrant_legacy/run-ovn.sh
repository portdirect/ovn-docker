IPAM_IP=$1 # 192.168.50.101
#LOCAL_OVS_IP=$2 #192.168.50.101

IPAM_IP=$1
LOCAL_OVS_IP=$(ip -f inet -o addr show eth1|cut -d\  -f 7 | cut -d/ -f 1)

ovn-integrate create-integration-bridge
ovn-integrate set-ipam $IPAM_IP
ovn-integrate set-tep $LOCAL_OVS_IP


ovs-vsctl set Open_vSwitch . external_ids:ovn-remote="tcp:$IPAM_IP:6642"
ovs-vsctl set Open_vSwitch . external_ids:ovn-nb="tcp:$IPAM_IP:6641"
ovs-vsctl set Open_vSwitch . external_ids:ovn-encap-ip="$LOCAL_OVS_IP"
ovs-vsctl set Open_vSwitch . external_ids:ovn-encap-type="geneve"



ovn-container init --bridge br-int --overlay-mode
/usr/share/openvswitch/scripts/ovn-ctl restart_controller
