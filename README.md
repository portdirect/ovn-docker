Neoprene: an OVN based K8s/Neutron network fabric
-----------------------------------------

Neoprene can create a logical network between Kubernetes pods and docker containers 
running on multiple hosts, using OVN to provide the underlying fabric. Capable of
mulch-tenant operation Neoprene provides robust and scalable networking for container
workloads.

Neoprene can be deployed as an alternative to Flannel or Calico in a stand alone
Rubbernecks cluster, or as part of the Harbor platform. When used within Harbor it
works in a separate Availability Zone (the under-cloud) from the public facing components
and provides both the k8s network layer for the OpenStack controllers, and the provider
Network for the end-user accessible Availability Zones.

This project is heavily based on the work of shettyg (https://github.com/shettyg/ovn-docker),
and is a fast moving target at the moment, but will aim to remain small and simple, focused on
providing effient globaliy distributed L2 networks and DVR functionality. Eventually Keystone
Federation, and a VPN layer (most likley either IPsec or WireGuard) will be incorporated to
improve deployment flexibility.
