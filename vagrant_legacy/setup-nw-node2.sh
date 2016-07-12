ovn-container endpoint-create ls0 ls0p2
NETWORK_CONTAINER=$(ovn-container container-create --network=ls0p2)
docker run -d --net=container:$NETWORK_CONTAINER --name networktest port/base:latest tail -f /dev/null
