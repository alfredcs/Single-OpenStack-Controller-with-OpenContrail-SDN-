# Single-OpenStack-Controller-with-OpenContrail-SDN-
This folder contains all needed component except rpms to stand up a single OpenStack controller node along with OpenContrail 
for Software Defined Network service in CentOS 6.5/RedHat6. It also include utility to stand up compute nodes to join the cloud.

Step to Stand up a single node OpenStack controller

1) Prepare kernel and OS
2) Setup OpenStack, Percona and OpenContrail repos
3) Install openstack-install1 
4) Run ./openstack-install1.sh -L -v <openstack_controller_vip> -r <openstack_repo_name,percona_repo_name,contrail_repo_name>

Step to standup a compute node

1) Prepare kernel and OS
2) Point to OpenStack and Contrail repos
3) Install compute-install1 rpm
4) Run ./coimpute-install1 -L -o <openstack_controller_vip> -r <openstack_repo_name,contrail_repo_name>

