#!/bin/bash

NODE_IP="$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)"
/usr/bin/docker run -d  \
--name etcd \
--net host \
--volume=/var/etcd:/var/etcd:rw \
--restart=always \
quay.io/coreos/etcd:v3.0.1 \
/usr/local/bin/etcd \
--initial-advertise-peer-urls "http://$NODE_IP:2380" \
--initial-cluster "default=http://${NODE_IP}:2380" \
--listen-client-urls 'http://localhost:2379,http://0.0.0.0:4001' \
--advertise-client-urls "http://$NODE_IP:4001"





/usr/bin/docker run -d --name kube-setup-files \
--net=host \
--volume=/data:/data \
gcr.io/google_containers/hyperkube-amd64:v1.3.0 \
/setup-files.sh \
IP:${NODE_IP},DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local


/usr/bin/docker run -d --name kube-apiserver --net=host \
--volume=/data:/srv/kubernetes:rw \
--restart=always \
gcr.io/google_containers/hyperkube-amd64:v1.3.0 \
/hyperkube apiserver \
--service-cluster-ip-range=10.10.0.1/24 \
--insecure-bind-address=0.0.0.0 \
--insecure-port=8080 \
--etcd-servers=http://127.0.0.1:2379 \
--admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota \
--client-ca-file=/srv/kubernetes/ca.crt \
--basic-auth-file=/srv/kubernetes/basic_auth.csv \
--min-request-timeout=300 \
--tls-cert-file=/srv/kubernetes/server.cert \
--tls-private-key-file=/srv/kubernetes/server.key \
--token-auth-file=/srv/kubernetes/known_tokens.csv \
--allow-privileged=true \
--v=2 \
--logtostderr=true

/usr/bin/docker run \
-d \
--name kube-controller-manager \
--net=host \
--volume=/data:/srv/kubernetes:rw \
--restart=always \
gcr.io/google_containers/hyperkube-amd64:v1.3.0 \
/hyperkube controller-manager \
--master=127.0.0.1:8080 \
--service-account-private-key-file=/srv/kubernetes/server.key \
--root-ca-file=/srv/kubernetes/ca.crt \
--min-resync-period=3m \
--v=2 \
--logtostderr=true



/usr/bin/docker run \
-d \
--name kube-scheduler \
--net=host\
--restart=always \
gcr.io/google_containers/hyperkube-amd64:v1.3.0 \
/hyperkube scheduler \
--master=127.0.0.1:8080 \
--v=2 \
--logtostderr=true


/usr/bin/docker run \
--name kuryr-raven \
--net=host \
-d \
-e SERVICE_CLUSTER_IP_RANGE=10.10.0.1/24 \
-e SERVICE_USER=admin \
-e SERVICE_TENANT_NAME=admin \
-e SERVICE_PASSWORD=password \
-e IDENTITY_URL=http://${NODE_IP}:35357/v2.0 \
-e OS_URL=http://${NODE_IP}:9696 \
-e K8S_API=http://127.0.0.1:8080 \
-v /var/log/kuryr:/var/log/kuryr:rw \
--restart=always \
docker.io/port/system-raven:latest


/usr/bin/docker run \
--name kubelet \
-d \
-e MASTER_IP=${NODE_IP}\
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
--net=host \
--privileged=true \
--pid=host \
docker.io/port/system-kubelet:latest /kubelet




KUBE_LATEST_VERSION="v1.3.0"
mkdir -p /usr/bin
curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBE_LATEST_VERSION}/bin/linux/amd64/kubectl > /usr/bin/kubectl
chmod +x /usr/bin/kubectl
kubectl get nodes







#ovn-container net-create ls0 192.168.1.0/24
#ovn-container endpoint-create ls0 ls0p1
#NETWORK_CONTAINER=$(ovn-container container-create --network=ls0p1)
#docker run -d --net=container:$NETWORK_CONTAINER --name networktest port/base:latest tail -f /dev/null
