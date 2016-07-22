#!/bin/bash
SCRIPT_URL=https://raw.githubusercontent.com/portdirect/neoprene/master/vagrant_legacy/install-ovn.sh
curl -s ${SCRIPT_URL} | bash -s

SCRIPT_URL=https://raw.githubusercontent.com/portdirect/neoprene/master/vagrant_legacy/run-ipam.sh
curl -s ${SCRIPT_URL} | bash -s

SCRIPT_URL=https://raw.githubusercontent.com/portdirect/neoprene/master/vagrant_legacy/setup-nw-node1.sh
curl -s ${SCRIPT_URL} | bash -s
