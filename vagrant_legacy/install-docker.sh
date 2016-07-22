#!/bin/sh
yum install -y docker
systemctl start docker
systemctl enable docker
