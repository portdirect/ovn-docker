#!/bin/bash
OS_DISTRO=HarborOS
################################################################################
echo "${OS_DISTRO}: SELINUX"
################################################################################
setenforce 0
cat > /etc/selinux/config <<EOF
# This file controls the state of SELinux on the system.
# SELINUX= can take one of these three values:
#     enforcing - SELinux security policy is enforced.
#     permissive - SELinux prints warnings instead of enforcing.
#     disabled - No SELinux policy is loaded.
SELINUX=disabled
# SELINUXTYPE= can take one of three two values:
#     targeted - Targeted processes are protected,
#     minimum - Modification of targeted policy. Only selected processes are protected.
#     mls - Multi Level Security protection.
SELINUXTYPE=targeted
EOF

################################################################################
echo "${OS_DISTRO}: DOCKER"
################################################################################
yum install -y docker bridge-utils
cat > /etc/systemd/system/docker-storage-setup.service <<EOF
[Unit]
Description=Docker Storage Setup
After=network.target
Before=docker.service
[Service]
Type=oneshot
ExecStart=/usr/bin/docker-storage-setup
EnvironmentFile=-/etc/sysconfig/docker-storage-setup
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start docker



################################################################################
echo "${OS_DISTRO}: OVS_KERNEL"
################################################################################
docker pull port/ovs-vswitchd:latest
docker run -d \
--name ovs-installer \
-v /srv \
port/ovs-vswitchd:latest tail -f /dev/null
OVS_RPM_DIR="$(docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/srv" }}{{ .Source }}{{ end }}{{ end }}' ovs-installer)"
yum install -y ${OVS_RPM_DIR}/x86_64/openvswitch-kmod*.rpm
yum install -y ${OVS_RPM_DIR}/x86_64/*.rpm ${OVS_RPM_DIR}/noarch/*.rpm
docker stop ovs-installer
docker rm -v ovs-installer
modprobe libcrc32c
modprobe nf_conntrack_ipv6
modprobe nf_nat_ipv6
modprobe gre
modprobe openvswitch
modprobe vport-geneve
modprobe vport-vxlan

################################################################################
echo "${OS_DISTRO}: OVS_USERSPACE"
################################################################################

cat > /etc/systemd/system/openvswitch-nonetwork.service <<EOF
[Unit]
Description=Open vSwitch Internal Unit
After=syslog.target docker.service
Requires=docker.service
PartOf=openvswitch.service
Wants=openvswitch.service
[Service]
Restart=always
RestartSec=10
RemainAfterExit=yes
ExecStartPre=/usr/local/bin/openvswitch-start
ExecStart=/usr/bin/bash -c 'echo "OVS Started"'
ExecStartStop=/usr/local/bin/openvswitch-stop
EOF

cat > /usr/local/bin/openvswitch-start << EOF
#!/bin/bash
setenforce 0

modprobe libcrc32c
modprobe nf_conntrack_ipv6
modprobe nf_nat_ipv6
modprobe gre
modprobe openvswitch
modprobe vxlan
modprobe vport-geneve
modprobe vport-vxlan

docker stop ovs-db || true
docker rm -v ovs-db || true
docker run -d \
--net=host \
--name ovs-db \
--restart=always \
-v /var/run/openvswitch:/var/run/openvswitch:rw \
-v /var/lib/ovn:/var/lib/ovn:rw \
port/ovsdb-server-node:latest

docker stop ovs-vswitchd || true
docker rm -v ovs-vswitchd || true
docker run -d \
--net=host \
--pid=host \
--ipc=host \
--name ovs-vswitchd \
--privileged \
--cap-add NET_ADMIN \
--restart=always \
-v /dev/net:/dev/net:rw \
-v /var/run/netns:/var/run/netns:rw \
-v /var/run/openvswitch:/var/run/openvswitch:rw \
-v /var/lib/ovn:/var/lib/ovn:rw \
port/ovs-vswitchd:latest

sleep 2s
ovs-vsctl --no-wait init
ovs-vsctl --no-wait set open_vswitch . system-type="HarborOS"
ovs-vsctl --no-wait set open_vswitch . external-ids:system-id="\$(hostname)"
EOF
chmod +x /usr/local/bin/openvswitch-start

systemctl daemon-reload
systemctl start openvswitch
systemctl enable openvswitch


################################################################################
echo "${OS_DISTRO}: OVN_NODE"
################################################################################

cat > /etc/systemd/system/ovn-controller.service <<EOF
[Unit]
Description=Open vSwitch Internal Unit
After=syslog.target docker.service
Requires=docker.service openvswitch.service

[Service]
Restart=always
RestartSec=10
RemainAfterExit=yes
ExecStartPre=/usr/local/bin/ovn-controller-start
ExecStart=/usr/bin/bash -c 'echo "OVN Controller Started"'
ExecStartStop=/usr/local/bin/ovn-controller-stop

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/bin/ovn-controller-start << EOF
#!/bin/bash
docker stop ovn-controller || true
docker rm -v ovn-controller || true
docker run -d \
--net=host \
--name ovn-controller \
--restart=always \
-v /var/run/openvswitch:/var/run/openvswitch:rw \
port/ovn-controller:latest
EOF
chmod +x /usr/local/bin/ovn-controller-start

cat > /usr/local/bin/ovn-controller-stop << EOF
#!/bin/bash
docker stop ovn-controller || true
docker rm -v ovn-controller || true
EOF
chmod +x /usr/local/bin/ovn-controller-stop

systemctl daemon-reload
systemctl start ovn-controller
systemctl enable ovn-controller
