#!/bin/bash

################################################################################
echo "${OS_DISTRO}: OVN_NORTHD"
################################################################################

cat > /etc/systemd/system/ovn-northd.service <<EOF
[Unit]
Description=Open vSwitch Internal Unit
After=syslog.target docker.service
Requires=docker.service openvswitch.service

[Service]
Restart=always
RestartSec=10
RemainAfterExit=yes
ExecStartPre=/usr/local/bin/ovn-northd-start
ExecStart=/usr/bin/bash -c 'echo "OVN Northd Started"'
ExecStartStop=/usr/local/bin/ovn-northd-stop
EOF

cat > /usr/local/bin/ovn-northd-start << EOF
#!/bin/bash
docker stop ovn-sb-db || true
docker rm -v ovn-sb-db || true
docker run -d \
--name ovn-sb-db \
-p 0.0.0.0:6642:6642/tcp \
-v /var/run/openvswitch:/var/run/openvswitch:rw \
port/ovsdb-server-sb:latest

docker stop ovn-nb-db || true
docker rm -v ovn-nb-db || true
docker run -d \
--name ovn-nb-db \
-p 0.0.0.0:6641:6641/tcp \
-v /var/run/openvswitch:/var/run/openvswitch:rw \
port/ovsdb-server-nb:latest

docker stop ovn-northd || true
docker rm -v ovn-northd || true
docker run -d \
--name ovn-northd \
port/ovn-northd:latest
EOF
chmod +x /usr/local/bin/ovn-northd-start

cat > /usr/local/bin/ovn-northd-stop << EOF
#!/bin/bash
docker stop ovn-northd || true
docker rm -v ovn-northd || true

docker stop ovn-nb-db || true
docker rm -v ovn-nb-db || true

docker stop ovn-sb-db || true
docker rm -v ovn-sb-db || true
EOF
chmod +x /usr/local/bin/ovn-northd-stop


systemctl daemon-reload
systemctl restart ovn-northd



OVN_IP=$(ip -f inet -o addr show eth1|cut -d\  -f 7 | cut -d/ -f 1)
docker run -d \
--name ipam \
-e EXPOSED_IP=${OVN_IP} \
-e OVN_NORTHD_IP=${OVN_IP} \
-p ${OVN_IP}:5000:5000 \
-p ${OVN_IP}:35357:35357 \
-p ${OVN_IP}:8774:8774 \
-p ${OVN_IP}:8775:8775 \
-p ${OVN_IP}:9696:9696 \
docker.io/port/ovn-ipam:latest tail -f /dev/null
