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

[Install]
WantedBy=multi-user.target
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






################################################################################
echo "${OS_DISTRO}: OPENSTACK"
################################################################################

cat > /etc/systemd/system/openstack.service <<EOF
[Unit]
Description=Openstack
After=syslog.target docker.service
Requires=docker.service openvswitch.service

[Service]
Restart=always
RestartSec=10
RemainAfterExit=yes
ExecStartPre=/usr/local/bin/openstack-start
ExecStart=/usr/bin/bash -c 'echo "Openstack Started"'
ExecStartStop=/usr/local/bin/openstack-stop

[Install]
WantedBy=multi-user.target
EOF


cat > /usr/local/bin/openstack-start << EOF
#!/bin/bash
docker stop openstack || true
docker rm -v openstack || true
OVN_IP=\$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)
docker run -d \
--name openstack \
-e EXPOSED_IP=\${OVN_IP} \
-e OVN_NORTHD_IP=\${OVN_IP} \
-p \${OVN_IP}:80:80 \
-p \${OVN_IP}:5000:5000 \
-p \${OVN_IP}:35357:35357 \
-p \${OVN_IP}:5672:5672 \
-p \${OVN_IP}:8774:8774 \
-p \${OVN_IP}:8775:8775 \
-p \${OVN_IP}:9696:9696 \
docker.io/port/ovn-ipam:latest /start.sh
EOF
chmod +x /usr/local/bin/openstack-start

cat > /usr/local/bin/openstack-stop << EOF
#!/bin/bash
docker stop openstack || true
docker rm -v openstack || true
EOF
chmod +x /usr/local/bin/openstack-stop


systemctl daemon-reload
docker pull docker.io/port/ovn-ipam:latest
systemctl restart openstack





cat > /usr/bin/wupiao <<EOF
#!/bin/bash
# [w]ait [u]ntil [p]ort [i]s [a]ctually [o]pen
[ -n "\$1" ] && \
    until curl -o /dev/null -sIf http://\${1}; do \
    sleep 1 && echo .;
  done;
exit \$?
EOF
chmod +x /usr/bin/wupiao

OVN_IP=$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)
/usr/bin/wupiao ${OVN_IP}:5000
/usr/bin/wupiao ${OVN_IP}:35357
/usr/bin/wupiao ${OVN_IP}:9696
