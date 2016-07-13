#!/bin/bash
docker run -d -p 9696:9696 -p 6640:6640 -p 6641:6641 -p 6642:6642 --name ipam docker.io/port/ovn-ipam:latest /start.sh
