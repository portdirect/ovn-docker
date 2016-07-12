ovn-container net-create ls0 192.168.1.0/24
ovn-container endpoint-create ls0 ls0p1
NETWORK_CONTAINER=$(ovn-container container-create --network=ls0p1)
docker run -d --net=container:$NETWORK_CONTAINER --name networktest port/base:latest tail -f /dev/null
