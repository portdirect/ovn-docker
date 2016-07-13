#!/bin/bash
OVN_IP=$(ip -f inet -o addr show eth1|cut -d\  -f 7 | cut -d/ -f 1)
docker run -d \
--name ipam \
-p ${OVN_IP}:5000:5000 \
-p ${OVN_IP}:9696:9696 \
-p ${OVN_IP}:6640:6640 \
-p ${OVN_IP}:6641:6641 \
-p ${OVN_IP}:6642:6642 \
docker.io/port/ovn-ipam:latest /start.sh
