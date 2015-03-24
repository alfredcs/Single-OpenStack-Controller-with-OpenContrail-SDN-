#!/bin/bash
set -x
function usage() {
cat <<EOF
usage: $0 options

This script will install openstack components on a controller node

Example:
        openstack_install.sh [-L] -v openstack_controller_vip [ -e glusterfs_vip] [-m glusterfs_volume_name] [-r repo_name1,repo_name2,... ]

OPTIONS:
  -h -- Help Show this message
  -g -- Glance Mysql password
  -G -- Glance Keystone password
  -L -- Use SSL for Keystone
  -e -- Glusterfs VIP
  -m -- Gluasterfs mount point volume name
  -n -- NOVA Mysql password
  -N -- NOVA Keystone password
  -r -- Repo server name or IP
  -R -- Mysql Root password
  -u -- Neutron Mysql password
  -U -- Neutron Keystone password
  -V -- Verbose Verbose output
  -v -- VIP of the openstack controller

EOF
}

function run_all_openstack() {
if [[ `uname -r` =~ ^3\. ]]; then
        systemctl $1 httpd
        systemctl $1 keepalived
        systemctl $1 haproxy
        systemctl $1 memcached
        [[ `ps -ef | grep haproxy | grep -v grep|wc -l` -gt 0 ]] &&  pkill haproxy
	systemctl $1 mysql@bootstrap.service
        systemctl $1 openstack-keystone
        systemctl $1 openstack-glance-api
        systemctl $1 openstack-glance-registry
        systemctl $1 openstack-nova-api
        systemctl $1 openstack-nova-cert
        systemctl $1 openstack-nova-conductor
        #systemctl $1 openstack-nova-console 
        systemctl $1 openstack-nova-consoleauth
        systemctl $1 openstack-nova-novncproxy
        systemctl $1 openstack-nova-scheduler
        systemctl $1 iptables
else
        service httpd $1
        service keepalived $1
        service memcached $1
        [[ `ps -ef | grep haproxy | grep -v grep|wc -l` -gt 0 ]] &&  pkill haproxy
        service haproxy $1
	service mysql $1 --wsrep-cluster-address="gcomm://"
        service openstack-keystone $1
        service openstack-glance-api $1
        service openstack-glance-registry $1
        service openstack-nova-api $1
        service openstack-nova-cert $1
        service openstack-nova-conductor $1
        #service openstack-nova-console $1
        service openstack-nova-consoleauth $1
        service openstack-nova-novncproxy $1
        service openstack-nova-scheduler $1
fi
}


function run_all_contrail() {
if [[ `uname -r` =~ ^3\. ]]; then
        systemctl $1 supervisor-analytics
        systemctl $1 supervisor-config
        systemctl $1 supervisor-contrail-database
        systemctl $1 supervisor-control
        systemctl $1 supervisor-webui
	systemctl $1 neutron-server
else    
	service supervisor-analytics $1
	service supervisor-config $1
	service supervisor-contrail-database $1
	service supervisor-control $1
	#service supervisor-support-service $1
	service supervisor-webui $1
	service neutron-server $1
fi
}

FIRST_CONTROLLER=""
SSL_FLAG=""
glusterfs_vip=""
glusterfs_vol=""
HTTP_CMD="http"
[[ `id -u` -ne 0 ]] && { echo  "Must be root!"; exit 0; }
[[ $# -lt 2 ]] && { usage; exit 1; }
while getopts "hg:G:Ln:N:r:R:u:U:v:e:m:VD" OPTION; do
case "$OPTION" in
h)
        usage
        exit 0
        ;;
e)
	glusterfs_vip="$OPTARG"
	;;
m)
	glusterfs_vol="$OPTARG"
	;;
g)
        GLANCE_DBPASS="$OPTARG"
        ;;
G)
        GLANCE_KSPASS="$OPTARG"
        ;;
L)	SSL_FLAG="-L"
	HTTP_CMD="https"
	;;
n)
        NOVA_DBPASS="$OPTARG"
        ;;
N)
        NOVA_KSPASS="$OPTARG"
        ;;
r)
	REPO_SERVER="$OPTARG"
	;;
R)
        MYSQL_ROOT_PASS="$OPTARG"
        ;;
v)
        controller=`grep "${OPTARG}\s" /etc/hosts | grep -v ^#|head -1|awk '{print $1}'`
        ;;
V)
        display_version
        exit 0
        ;;
u)
        NEUTRON_DBPASS="$OPTARG"
        ;;
U)
        NEUTRON_KSPASS="$OPTARG"
        ;;
D)
        DEBUG=1
        ;;
\?)
        echo "Invalid option: -"$OPTARG"" >&2
        usage
        exit 1
        ;;
:)
        usage
        exit 1
        ;;
esac
done

host_name=`echo $HOSTNAME| cut -d\. -f1`
local_controller=`grep "${host_name}\s" /etc/hosts|grep -v ^#|head -1|awk '{print $1}'`
FIRST_CONTROLLER=${local_controller}
if [[  ${FIRST_CONTROLLER} == ${local_controller}  ]]; then
	ADMIN_PASS=${ADMIN_PASS:-$(openssl rand -hex 10)}
	contAdmin_PASS=${contAdmin_PASS:-$(openssl rand -hex 10)}
	KEYSTONE_DBPASS=${KEYSTONE_DBPASS:-$(openssl rand -hex 10)}
	GLANCE_DBPASS=${GLANCE_DBPASS:-$(openssl rand -hex 10)}
	NOVA_DBPASS=${NOVA_DBPASS:-$(openssl rand -hex 10)}
	GLANCE_KSPASS=${GLANCE_KSPASS:-$(openssl rand -hex 10)}
	NOVA_KSPASS=${NOVA_KSPASS:-$(openssl rand -hex 10)}
	NEUTRON_KSPASS=${NEUTRON_KSPASS:-$(openssl rand -hex 10)}
	MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS:-$(openssl rand -hex 10)}
	ADMIN_TOKEN=$(openssl rand -hex 10)
	controller=${controller:-"${controller}"}
	contrail_controller=${contrail_controller:-"$controller"}
	[[ -f ./.keystone_grants ]] && rm -f ./.keystone_grants
	#NODE_INDEX="-F"
	#[[ ${FIRST_CONTROLLER} == 0 ]] && NODE_INDEX="-S"
	echo "#Keystone grants created on `date`" >> ./.keystone_grants
	echo "SSL_FLAG=${SSL_FLAG}">>./.keystone_grants
	echo "ADMIN_KSPASS=${ADMIN_PASS}" >> ./.keystone_grants
	echo "KEYSTONE_DBPASS=${KEYSTONE_DBPASS}" >> ./.keystone_grants
	echo "NEUTRON_KSPASS=${NEUTRON_KSPASS}" >> ./.keystone_grants
	echo "NOVA_KSPASS=${NOVA_KSPASS}" >> ./.keystone_grants
	echo "NOVA_DBPASS=${NOVA_DBPASS}" >> ./.keystone_grants
	echo "GLANCE_KSPASS=${GLANCE_KSPASS}" >> ./.keystone_grants
	echo "GLANCE_DBPASS=${GLANCE_DBPASS}" >> ./.keystone_grants
	echo "MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS}" >> ./.keystone_grants
	echo "openstack_controller=${controller}" >> ./.keystone_grants
	echo "contrail_controller=${contrail_controller}" >> ./.keystone_grants
	echo "OS_SERVICE_TOKEN=${ADMIN_TOKEN}"  >> ./.keystone_grants
	echo "contAdmin_PASS=${contAdmin_PASS}"  >> ./.keystone_grants
else
	###
        # Get Keys
        ###
        [[ -f .keystone_grants ]] && { rm -rf .keystone_grants; rm -rf keystone_grants.enc; }
        curl --insecure -o keystone_grants.enc ${HTTP_CMD}://${FIRST_CONTROLLER}/.tmp/keystone_grants.enc
	[[  -f keystone/newkey.pem && -f keystone_grants.enc ]] && openssl rsautl -decrypt -inkey keystone/newkey.pem -in keystone_grants.enc -out .keystone_grants
	[[ ! -f  ./.keystone_grants ]] && { echo "Require credential file from Openstacl installation!"; exit 1; }
        ADMIN_KSPASS=${ADMIN_KSPASS:-`cat ./.keystone_grants|grep -i ADMIN_KSPASS| grep -v ^#|cut -d= -f2`}
        contAdmin_PASS=${contAdmin_PASS:-`cat ./.keystone_grants|grep -i contAdmin_PASS| grep -v ^#|cut -d= -f2`}
        KEYSTONE_DBPASS=${KEYSTONE_DBPASS:-`cat ./.keystone_grants|grep -i KEYSTONE_DBPASS| grep -v ^#|cut -d= -f2`}
        GLANCE_DBPASS=${GLANCE_DBPASS:-`cat ./.keystone_grants|grep -i GLANCE_DBPASS| grep -v ^#|cut -d= -f2`}
        NOVA_DBPASS=${NOVA_DBPASS:-`cat ./.keystone_grants|grep -i NOVA_DBPASS| grep -v ^#|cut -d= -f2`}
        GLANCE_KSPASS=${GLANCE_KSPASS:-`cat ./.keystone_grants|grep -i GLANCE_KSPASS| grep -v ^#|cut -d= -f2`}
        NOVA_KSPASS=${NOVA_KSPASS:-`cat ./.keystone_grants|grep -i NOVA_KSPASS| grep -v ^#|cut -d= -f2`}
        NEUTRON_KSPASS=${NEUTRON_KSPASS:-`cat ./.keystone_grants|grep -i NEUTRON_KSPASS| grep -v ^#|cut -d= -f2`}
        MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS:-`cat ./.keystone_grants|grep -i MYSQL_ROOT_PASS| grep -v ^#|cut -d= -f2`}
        ADMIN_TOKEN=${ADMIN_TOKEN:-`cat ./.keystone_grants|grep -i ADMIN_TOKEN| grep -v ^#|cut -d= -f2`}
	controller=${controller:-`cat ./.keystone_grants|grep -i openstack_controller| grep -v ^#|cut -d= -f2`}
	contrail_controller=${contrail_controller:-`cat ./.keystone_grants|grep -i contrail_controller| grep -v ^#|cut -d= -f2`}
fi

####
# Clean up 
####
for file_n in keystone glance nova mysql haproxy
do
    [[ /data/var/lib/${file_n} ]] && rm -fr /data/var/lib/${file_n}
    [[ /var/lib/${file_n} ]] && rm -fr /var/lib/${file_n}
    [[ /data/var/log/${file_n} ]] && rm -fr /data/var/log/${file_n} 
    [[ /var/log/${file_n} ]] && rm -fr /var/log/${file_n}
done
umount -f `df -k|grep glance|awk '{print $1}'` > /dev/null 2>&1

##
# Open up iptables
##
iptables -A INPUT -p tcp --dport 5672:5673 -j ACCEPT
iptables -A INPUT -p tcp --dport 4567 -j ACCEPT
iptables -A INPUT -p tcp --dport 3306 -j ACCEPT
iptables -A INPUT -p tcp --dport 35357 -j ACCEPT
iptables -A INPUT -p tcp --dport 5000 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables-save

####
# Stop all services
####
run_all_openstack stop
run_all_contrail stop

###
# Clean up
###
for file_n in contrail cassandra zookeeper neutron redis /etc/keepalived/keepalived.conf /etc/my.cnf /etc/haproxy/haproxy.cnf
do
    [[ /data/var/lib/${file_n} ]] && rm -fr /data/var/lib/${file_n}
    [[ /var/lib/${file_n} ]] && rm -fr /var/lib/${file_n}
    [[ /data/var/log/${file_n} ]] && rm -fr /data/var/log/${file_n}
    [[ /var/log/${file_n} ]] && rm -fr /var/log/${file_n}
    [[ /etc/${file_n} ]] && rm -fr /etc/${file_n}
    [[ ${file_n} ]] && rm -fr ${file_n}
    [[ /data/${file_n} ]] && rm -fr /data/${file_n}
done

[[ -d /tmp/keystone-signing* ]] && { rm -f /tmp/keystone-signing*; rm -rf ~/keystone-signing; }
###
# Install haproxy and keepalived
###
[[ -f ./ha_install.sh ]] && ./ha_install.sh ${SSL_FLAG} -v $controller -r ${REPO_SERVER}
[[ $? -ne 0 ]] && { echo "Install HA failure, Abort!!!"; exit 1; }

##
# Install contrail-openstack-config
##
[[ -d ~/keystone-signing ]] && rm -rf ~/keystone-signing

[[ `rpm -qa | grep -Ei 'Percona|contrail|mysql|nova' | wc -l` -gt 0 ]] && rpm -e --nodeps `rpm -qa | grep -Ei 'Percona|contrail|mysql|nova'`
# Remove old installations
yum -y erase -x contrail-openstack-config `rpm -qa | egrep -i 'neutron|contrail|supervisor|cassandra|zookeeper'`; rpm -e --nodeps supervisor redis gmp gmp-devel python-bitarray
for conf_file in /opt/contrail /home/cassandra /var/lib/cassandra /var/lib/zookeeper /var/lib/redis
do
         [[ -d ${conf_file} ]] && rm -rf ${conf_file}
done
yum -y install --disablerepo=* --enablerepo=${REPO_SERVER} gmp gmp-devel
[[ ! -f /usr/lib64/libgmp.so.3 ]] && ln -s /usr/lib64/libgmp.so /usr/lib64/libgmp.so.3
yum -y install --disablerepo=* --enablerepo=`echo ${REPO_SERVER}|sed 's/havana.*\,//' | sed 's/\,havana.*//'` \
	contrail-openstack-config  contrail-config-openstack \
        contrail-openstack-analytics \
        contrail-openstack-database contrail-openstack-control \
        contrail-openstack-webui supervisor.x86_64 contrail-config redis \
        contrail-web-controller contrail-web-core python-bitarray
[[ $? -ne 0 ]] && { echo "Package install failed on Contrail!"; exit 1; }
[[ `rpm -qa | grep -E 'mysql|nova|quantum' | wc -l` -gt 0 ]] && rpm -e --nodeps `rpm -qa | grep -E 'mysql|nova|quantum'` 

##
# Install keystone
##
[[ -f ./keystone_install.sh ]] && ./keystone_install.sh  ${SSL_FLAG} -v $controller -r ${REPO_SERVER}
[[ $? -ne 0 ]] && { echo "Install Keystone failure, Abort!!!"; exit 1; }
##
# Install glance
##
[[ -f ./glance_install.sh ]] && ./glance_install.sh  ${SSL_FLAG} -v $controller -r ${REPO_SERVER}
[[ $? -ne 0 ]] && { echo "Install Glance failure, Abort!!!"; exit 1; }
###
# Install nova
###
[[ -f ./nova_install.sh ]]  && ./nova_install.sh  ${SSL_FLAG} -v $controller -r ${REPO_SERVER}
[[ $? -ne 0 ]] && { echo "Install Nova failure, Abort!!!"; exit 1; }
##
# Install neutron endpoint
##
[[ -f ./neutron_install.sh ]]  && ./neutron_install.sh  ${SSL_FLAG} -v $controller -r ${REPO_SERVER}
[[ $? -ne 0 ]] && { echo "Install Neutron failure, Abort!!!"; exit 1; }
###
# Install Horizon
###
[[ -f ./horizon_install.sh ]]  && ./horizon_install.sh   ${SSL_FLAG} -v $controller -r ${REPO_SERVER}
#[[ $? -ne 0 ]] && { echo "Install Horizon failure, Abort!!!"; exit 1; }
###
# Pass credential
###
openssl rsautl -encrypt -pubin -inkey keystone/newpub.pem -in ./.keystone_grants -out keystone_grants.enc
if [[ -d /var/www/html ]]; then
	mkdir -p /var/www/html/.tmp
	[[ -f /var/www/html/.tmp/keystone_grants.enc ]] && rm -f /var/www/html/.tmp/keystone_grants.enc
	[[ -f keystone_grants.enc ]] && /bin/cp -pf keystone_grants.enc /var/www/html/.tmp/
	cd /etc/keystone
	tar cpf keystone_ssl.tar ssl
	openssl enc -aes-256-cfb -kfile /var/lib/rabbitmq/.erlang.cookie -in keystone_ssl.tar -out /var/www/html/.tmp/keystone_ssl.tar.enc 
	[[ -f keystone_ssl.tar ]] &&  rm -f keystone_ssl.tar
	cd - 
else
	curl --insecure -o keystone_ssl.tar.enc https://${controller}/.tmp/keystone_ssl.tar.enc
	openssl enc -aes-256-cfb -d -kfile /var/lib/rabbitmq/.erlang.cookie -in keystone_ssl.tar.enc -out /etc/keystone/keystone_ssl.tar
	cd /etc/keystone
	mv ./ssl ./ssl.orig
	[[ -f keystone_ssl.tar ]] && tar xpf keystone_ssl.tar
	i[[ -f keystone_ssl.tar ]] && rm -f keystone_ssl.tar
	cd - 
fi
#if [[ -f .keystone_grants ]]; then
#	[[ ! -d /var/www/html/.tmp ]] && { mkdir -p /var/www/html/.tmp; /bin/cp -p ./keystone_grants.enc /var/www/html/.tmp/; }
#	rm -f ./keystone_grants.enc
#	rm -f .keystone_grants
#fi

##
# Add space 
#
[[ ! -d /data && `grep vda2 /etc/fstab|wc -l` -lt 1 ]] && echo "/dev/vda2  /data   ext4    defaults    0 0" >> /etc/fstab
[[ ! -d /data ]] && mkdir -p /data
if [[ ! -e /dev/vda2 && -e /dev/vda ]]; then
        (echo n; echo p;echo 2; echo; echo +50G;echo w;echo q)| fdisk /dev/vda
        partx -v -a /dev/vda
        mkfs -t ext4 /dev/vda2
fi
[[ ! -e /data/lost+found ]] && mount /data
[[ -d /data/var/lib ]] && rm -rf /data/var/lib
[[ -d /data/var/log ]] && rm -rf /data/var/log

service rabbitmq-server stop 
[[ `ps -ef| grep epmd|grep -v grep|wc -l` -gt 0 ]] && pkill epmd
sleep 1
[[ `ps -ef| grep epmd|grep -v grep|wc -l` -gt 0 ]] && kill -9 `ps -ef| grep epmd|grep -v grep| awk '{print $2}'`
[[ -d /var/lib/rabbitmq/mnesia ]] && rm -rf /var/lib/rabbitmq/mnesia

stop_all
if [[ ! -d /data/var/lib/nova ]]; then
        mkdir -p /data/var/lib
	for file_n in keystone nova mysql haproxy
        do
        	[[ -d /var/lib/${file_n} ]] && mv -f /var/lib/${file_n} /data/var/lib
		[[ ! -d /var/lib/${file_n} ]] && mkdir -p /data/var/lib/${file_n}
        	ln -sf /data/var/lib/${file_n} /var/lib/${file_n}
	done
fi
if [[ ! -d /data/var/log/nova ]]; then
        mkdir -p /data/var/log
	for file_n in keystone glance nova haproxy
	do
        	[[ -d /var/log/${file_n} ]] && mv -f /var/log/${file_n} /data/var/log
		[[ ! -d /var/log/${file_n} ]] && mkdir -p /data/var/log/${file_n}
        	ln -sf /data/var/log/${file_n} /var/log/${file_n}
	done
fi

####
# Enable shared glance volume based on glusterfs
##
if [[ ! -z ${glusterfs_vip} && ! -z ${glusterfs_vol} ]]; then
	[[ `rpm -qa | grep glusterfs|wc -l` -gt 0 ]] && rpm -e --nodeps `rpm -qa | grep glusterfs`
	yum -y install --disablerepo=* --enablerepo=${REPO_SERVER} glusterfs glusterfs-fuse glusterfs-rdma
	[[ $? -ne 0 ]] && { echo "Install glusterfs client failed!"; exit 1; }
	[[ -d /var/lib/glance ]] && rm -rf /var/lib/glance
	mkdir -p /var/lib/glance
	mount -t glusterfs ${glusterfs_vip}:/${glusterfs_vol} /var/lib/glance
	[[ $? -ne 0 ]] && { echo "Mount glusterfs server failed!"; exit 1; }
	[[ ! -d /var/lib/glance/images ]] && { mkdir -p /var/lib/glance/images; chown -R glance:glance /var/lib/glance; }
else
	mv -f /var/lib/glance /data/var/lib
	ln -sf /data/var/lib/glance /var/lib/glance
fi

##
# Start services
## 
#service rabbitmq-server start 
#if [[ ${local_controller} == ${local_controller} ]]; then
#	/etc/init.d/mysql restart --wsrep_cluster_address="gcomm://"
#	/usr/sbin/rabbitmqctl set_policy cluster-all-queues '^(?!amq\.).*' '{"ha-mode":"all","ha-sync-mode":"automatic"}'
#else
#	/etc/init.d/mysql restart
#fi

run_all_openstack restart

## 
# install Contrail
##
[[ -d ../sdn-install1 ]] && {
	cd ../sdn-install1;
	./contrail_neutron_install1.sh  ${SSL_FLAG} -o $controller -r `echo ${REPO_SERVER}|sed 's/havana.*\,//' | sed 's/\,havana.*//'` ;
	cd -;
}
keystone --insecure user-password-update --pass ${NEUTRON_KSPASS} neutron
run_all_openstack restart
run_all_contrail restart
