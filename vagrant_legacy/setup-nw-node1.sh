#!/bin/bash
NODE_IP=$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)
MASTER_IP=$NODE_IP
echo "${NODE_IP} $(hostname -s).novalocal $(hostname -s)" >> /etc/hosts
cat > /etc/yum.repos.d/docker.repo <<EOF
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF

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
yum install -y docker-engine bridge-utils
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


cat > /etc/systemd/system/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target

[Service]
Type=notify

ExecStartPre=-/sbin/rmmod vport_geneve
ExecStartPre=-/sbin/rmmod vport_vxlan
ExecStartPre=-/sbin/rmmod openvswitch
ExecStartPre=-/sbin/rmmod gre
ExecStartPre=-/sbin/rmmod vxlan
ExecStartPre=-/sbin/rmmod nf_nat_ipv6
ExecStartPre=-/sbin/rmmod nf_conntrack_ipv6

ExecStartPre=-/sbin/modprobe libcrc32c
ExecStartPre=-/sbin/modprobe nf_conntrack_ipv6
ExecStartPre=-/sbin/modprobe nf_nat_ipv6
ExecStartPre=-/sbin/modprobe gre
ExecStartPre=-/sbin/modprobe openvswitch
ExecStartPre=-/sbin/modprobe vxlan
ExecStartPre=-/sbin/modprobe vport-geneve
ExecStartPre=-/sbin/modprobe vport-vxlan
ExecStartPre=/usr/bin/bash -c 'mkdir -p /usr/lib/docker/plugins/kuryr; echo "http://127.0.0.1:23750" > /usr/lib/docker/plugins/kuryr/kuryr.spec'
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker

ExecStartPre=-/sbin/modprobe overlay

ExecStart=/usr/bin/docker daemon -s overlay -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375 --cluster-advertise=eth0:2375 --cluster-store etcd://${MASTER_IP}:4001
MountFlags=slave
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart docker

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
#yum install -y ${OVS_RPM_DIR}/x86_64/*.rpm ${OVS_RPM_DIR}/noarch/*.rpm
docker stop ovs-installer
docker rm -v ovs-installer
systemctl daemon-reload
systemctl restart docker

cat > /usr/bin/ovs-vsctl <<EOF
#!/bin/sh
exec docker run -t --rm \
--net=host \
-v /var/run/openvswitch:/var/run/openvswitch:rw \
docker.io/port/ovsdb-server-node ovs-vsctl "\$@"
EOF
chmod +x /usr/bin/ovs-vsctl
cat > /usr/bin/ovs-ofctl <<EOF
#!/bin/sh
exec docker run -t --rm \
--net=host \
-v /var/run/openvswitch:/var/run/openvswitch:rw \
docker.io/port/ovsdb-server-node ovs-ofctl "\$@"
EOF
chmod +x /usr/bin/ovs-ofctl


cat > /usr/bin/ovn-nbctl <<EOF
#!/bin/sh
exec docker run -t --rm \
--net=host \
-v /var/run/openvswitch:/var/run/openvswitch:rw \
docker.io/port/ovsdb-server-nb ovn-nbctl "\$@"
EOF
chmod +x /usr/bin/ovn-nbctl
cat > /usr/bin/ovn-sbctl <<EOF
#!/bin/sh
exec docker run -t --rm \
--net=host \
-v /var/run/openvswitch:/var/run/openvswitch:rw \
docker.io/port/ovsdb-server-sb ovn-sbctl "\$@"
EOF
chmod +x /usr/bin/ovn-sbctl




cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet Service
Documentation=https://docs.docker.com
After=network-online.target cloud-init.service chronyd.service docker.service
Requires=docker.service
Wants=network-online.target

[Service]
ExecStartPre=/usr/local/bin/kubelet-daemon-start
ExecStart=/usr/local/bin/kubelet-daemon-monitor
ExecStop=/usr/local/bin/kubelet-daemon-stop
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF


cat > /usr/local/bin/kubelet-daemon-start <<EOF
#!/bin/sh
KUBE_DEV=eth0
NODE_IP="\$(ip -f inet -o addr show \${KUBE_DEV}|cut -d\  -f 7 | cut -d/ -f 1)"

docker rm -v -f kubelet || true

exec docker run \
--name kubelet \
-d \
-e "MASTER_IP=${NODE_IP}" \
--restart=always \
--volume=/:/rootfs:ro \
--volume=/dev/net:/dev/net:rw \
--volume=/var/run/netns:/var/run/netns:rw \
--volume=/var/run/openvswitch:/var/run/openvswitch:rw \
--volume=/sys:/sys:ro \
--volume=/var/lib/docker/:/var/lib/docker:rw \
--volume=/var/lib/kubelet/:/var/lib/kubelet:rw \
--volume=/var/run:/var/run:rw \
--volume=/var/log/kuryr:/var/log/kuryr \
--volume=/etc/kubernetes/manifests:/etc/kubernetes/manifests:rw \
--net=host \
--privileged=true \
--pid=host \
docker.io/port/system-kubelet:latest /kubelet
EOF
chmod +x /usr/local/bin/kubelet-daemon-start

cat > /usr/local/bin/kubelet-daemon-monitor <<EOF
#!/bin/sh
exec docker wait kubelet
EOF
chmod +x /usr/local/bin/kubelet-daemon-monitor

cat > /usr/local/bin/kubelet-daemon-stop <<EOF
#!/bin/sh
docker stop kubelet || true
#(docker ps | awk '{ if (\$NF ~ "^k8s_") print \$1 }' | xargs -l1 docker stop) || true
docker rm -v -f kubelet || true
EOF
chmod +x /usr/local/bin/kubelet-daemon-stop



cat > /etc/systemd/system/swarm.service <<EOF
[Unit]
Description=Docker Swarm Service
Documentation=https://docs.docker.com
After=network-online.target cloud-init.service chronyd.service docker.service
Requires=docker.service
Wants=network-online.target

[Service]
ExecStartPre=/usr/local/bin/swarm-daemon-start
ExecStart=/usr/local/bin/swarm-daemon-monitor
ExecStop=/usr/local/bin/swarm-daemon-stop
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF


cat > /usr/local/bin/swarm-daemon-start <<EOF
#!/bin/sh
SWARM_DEV=eth0
NODE_IP="\$(ip -f inet -o addr show \${SWARM_DEV}|cut -d\  -f 7 | cut -d/ -f 1)"
MASTER_IP=\$NODE_IP
docker rm -v -f swarm || true
exec docker run \
      -d \
      --restart=always \
      --name swarm \
      --net=host \
      docker.io/port/system-swarm:latest \
          join \
          --advertise=\${NODE_IP}:2375 \
          etcd://\${MASTER_IP}:4001
EOF
chmod +x /usr/local/bin/swarm-daemon-start

cat > /usr/local/bin/swarm-daemon-monitor <<EOF
#!/bin/sh
exec docker wait swarm
EOF
chmod +x /usr/local/bin/swarm-daemon-monitor

cat > /usr/local/bin/swarm-daemon-stop <<EOF
#!/bin/sh
docker stop swarm || true
docker rm -v -f swarm || true
EOF
chmod +x /usr/local/bin/swarm-daemon-stop





cat > /etc/systemd/system/swarm-manager.service <<EOF
[Unit]
Description=Docker Swarm Service
Documentation=https://docs.docker.com
After=network-online.target cloud-init.service chronyd.service docker.service
Requires=docker.service
Wants=network-online.target

[Service]
ExecStartPre=/usr/local/bin/swarm-manager-daemon-start
ExecStart=/usr/local/bin/swarm-manager-daemon-monitor
ExecStop=/usr/local/bin/swarm-manager-daemon-stop
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF


cat > /usr/local/bin/swarm-manager-daemon-start <<EOF
#!/bin/sh
SWARM_DEV=eth0
NODE_IP="\$(ip -f inet -o addr show \${SWARM_DEV}|cut -d\  -f 7 | cut -d/ -f 1)"
MASTER_IP=\$NODE_IP
docker rm -v -f swarm-manager || true
exec docker run \
      -d \
      --restart=always \
      --name swarm-manager \
      --net=host \
      -v /var/run/swarm:/var/run/swarm:rw \
      docker.io/port/system-swarm:latest \
          manage \
          etcd://\${MASTER_IP}:4001 \
          -H unix:///var/run/swarm/docker.sock
EOF
chmod +x /usr/local/bin/swarm-manager-daemon-start

cat > /usr/local/bin/swarm-manager-daemon-monitor <<EOF
#!/bin/sh
exec docker wait swarm-manager
EOF
chmod +x /usr/local/bin/swarm-manager-daemon-monitor

cat > /usr/local/bin/swarm-manager-daemon-stop <<EOF
#!/bin/sh
docker stop swarm-manager || true
docker rm -v -f swarm-manager || true
EOF
chmod +x /usr/local/bin/swarm-manager-daemon-stop









cat > /usr/bin/kubectl <<EOF
#!/bin/sh
exec docker run -t --rm \
--net=host \
-v /:/rootfs:ro \
port/undercloud-kubectl:latest /usr/bin/kubectl "\$@"
EOF
chmod +x /usr/bin/kubectl


cat > /usr/bin/openstack <<EOF
#!/bin/bash
CONTROLLER_IP=\$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)
docker run -t --rm \
-e EXPOSED_IP=\${CONTROLLER_IP} \
-e OS_REGION_NAME="RegionOne" \
-e OS_PROJECT_NAME="admin" \
-e OS_DOMAIN_NAME="default" \
-e OS_IDENTITY_API_VERSION="3" \
-e OS_PASSWORD="password" \
-e OS_AUTH_URL="http://\${CONTROLLER_IP}:35357/v3" \
-e OS_USERNAME="admin" \
-e OS_TENANT_NAME="admin" \
docker.io/port/undercloud-openstackclient openstack "\$@"
EOF
chmod +x /usr/bin/openstack


cat > /usr/bin/nova <<EOF
#!/bin/bash
CONTROLLER_IP=\$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)
docker run -t --rm \
-e EXPOSED_IP=\${CONTROLLER_IP} \
-e OS_REGION_NAME="RegionOne" \
-e OS_PROJECT_NAME="admin" \
-e OS_IDENTITY_API_VERSION="3" \
-e OS_PASSWORD="password" \
-e OS_AUTH_URL="http://\${CONTROLLER_IP}:35357/v3" \
-e OS_USERNAME="admin" \
docker.io/port/undercloud-novaclient nova "\$@"
EOF
chmod +x /usr/bin/nova


cat > /usr/bin/docker-to-glance <<EOF
#!/bin/bash
docker pull "\$@"
docker tag "\$@" "\$@"
CONTROLLER_IP=\$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)
docker run -t --rm \
-e EXPOSED_IP=\${CONTROLLER_IP} \
-e OS_REGION_NAME="RegionOne" \
-e OS_PROJECT_NAME="admin" \
-e OS_DOMAIN_NAME="default" \
-e OS_IDENTITY_API_VERSION="3" \
-e OS_PASSWORD="password" \
-e OS_AUTH_URL="http://\${CONTROLLER_IP}:35357/v3" \
-e OS_USERNAME="admin" \
-e OS_TENANT_NAME="admin" \
-v /var/run/docker.sock:/var/run/docker.sock:rw \
docker.io/port/undercloud-openstackclient /bin/sh -c "docker save "\$@" | openstack image create "\$@" --public --container-format docker --disk-format raw"
EOF
chmod +x /usr/bin/docker-to-glance


cat > /usr/bin/neutron <<EOF
#!/bin/bash
CONTROLLER_IP=\$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)
docker run -t --rm \
-e EXPOSED_IP=\${CONTROLLER_IP} \
-e OS_REGION_NAME="RegionOne" \
-e OS_PROJECT_NAME="admin" \
-e OS_DOMAIN_NAME="default" \
-e OS_IDENTITY_API_VERSION="3" \
-e OS_PASSWORD="password" \
-e OS_AUTH_URL="http://\${CONTROLLER_IP}:35357/v3" \
-e OS_USERNAME="admin" \
-e OS_TENANT_NAME="admin" \
docker.io/port/undercloud-neutronclient neutron "\$@"
EOF
chmod +x /usr/bin/neutron


cat > /usr/bin/undercloud-bootstrap <<EOF
#!/bin/bash
CONTROLLER_IP=\$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)
docker run -t --rm \
-e CONTROLLER_IP=\${CONTROLLER_IP} \
-e KEYSTONE_SERVICE_HOST=\${CONTROLLER_IP} \
-e OS_REGION_NAME="RegionOne" \
-e OS_PROJECT_NAME="admin" \
-e OS_DOMAIN_NAME="default" \
-e OS_IDENTITY_API_VERSION="3" \
-e OS_PASSWORD="password" \
-e OS_AUTH_URL="http://\${CONTROLLER_IP}:35357/v3" \
-e OS_USERNAME="admin" \
-e OS_TENANT_NAME="admin" \
docker.io/port/undercloud-openstackclient /undercloud-bootstrap.sh
EOF
chmod +x /usr/bin/undercloud-bootstrap






systemctl restart kubelet
docker exec kubelet /usr/bin/undercloud-ctl
/usr/bin/undercloud-bootstrap
systemctl restart swarm
systemctl restart swarm-manager
systemctl restart swarm-manager


/usr/bin/docker-to-glance ewindisch/cirros:latest
/usr/bin/docker-to-glance docker.io/nginx:latest
