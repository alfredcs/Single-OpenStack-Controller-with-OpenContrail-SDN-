#!/bin/bash
set -x
function usage() {
cat <<EOF
usage: $0 options

This script will Nova on this Openstack Controller on a 3-node. 

Example:
        nova_install.sh [-L] -v openstack_controller [ -r repo_names_speerated_by_comma ]

OPTIONS:
  -h -- Help Show this message
  -L -- Use SSL for Keystone
  -r -- Repo names i.e. repo1,repo2,repo3
  -V -- Verbose Verbose output
  -v -- VIP of the openstack controller

EOF
}
KEYSTONE_CMD=keystone
HTTP_CMD=http
[[ `id -u` -ne 0 ]] && { echo  "Must be root!"; exit 0; }
[[ $# -lt 1 ]] && { usage; exit 1; }
while getopts "hLr:v:V" OPTION; do
case "$OPTION" in
h)
        usage
        exit 0
        ;;
L)
	KEYSTONE_CMD="keystone --insecure"
        HTTP_CMD="https"
	;;
r)
	REPO_SERVERS="$OPTARG"
	;;
v)
        openstack_controller="$OPTARG"
        ;;
V)
        display_version
        exit 0
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
local_controller=`egrep $HOSTNAME /etc/hosts|grep -v ^#|head -1|awk '{print $1}'`
if [[  ${local_controller} == ${local_controller}  ]]; then
        echo "Installing Nova on the first Openstack controller node ......"
else
        ###
        # Get Keys
        ###
        [[ -f .keystone_grants ]] && { rm -rf .keystone_grants; rm -rf eystone_grants.enc; }
        curl --insecure -o keystone_grants.enc https://${openstack_controller}/.tmp/keystone_grants.enc
        [[  -f keystone/newkey.pem && -f keystone_grants.enc ]] && openssl rsautl -decrypt -inkey keystone/newkey.pem -in keystone_grants.enc -out .keystone_grants
        [[ ! -f  ./.keystone_grants ]] && { echo "Require credential file from Openstacl installation!"; exit 1; }
fi

NOVA_DBPASS=${NOVA_DBPASS:-`cat ./.keystone_grants|grep -i NOVA_DBPASS| grep -v ^#|cut -d= -f2`}
NOVA_KSPASS=${NOVA_KSPASS:-`cat ./.keystone_grants|grep -i NOVA_KSPASS| grep -v ^#|cut -d= -f2`}
NEUTRON_KSPASS=${NEUTRON_KSPASS:-`cat ./.keystone_grants|grep -i NEUTRON_KSPASS| grep -v ^#|cut -d= -f2`}
MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS:-`cat ./.keystone_grants|grep -i MYSQL_ROOT_PASS| grep -v ^#|cut -d= -f2`}
openstack_controller=${openstack_controller:-`cat ./.keystone_grants|grep -i openstack_controller| grep -v ^#|cut -d= -f2`}
this_domain=`echo $HOSTNAME|cut -d\. -f2,3,4,5`
this_domain=${this_domain:-"default.domain"}
source ~/contrc
for nova_proc in openstack-nova-api openstack-nova-cert openstack-nova-conductor openstack-nova-consoleauth openstack-nova-novncproxy openstack-nova-scheduler
do
	[[ `uname -r` =~ ^3\. ]] && systemctl stop ${nova_proc}
	[[ `uname -r` =~ ^2\. ]] && service ${nova_proc} stop
done
[[ `rpm -qa | grep nova|wc -l` -gt 0 ]] && rpm -e --nodeps `rpm -qa|egrep 'python-novaclient|openstack-nova|nova|amqp'`
[[ `rpm -qa | grep gnutls|wc -l` -gt 0 ]] && rpm -e --nodeps `rpm -qa|egrep gnutls`
sed -i "/ossecd/ s/107/307/" /etc/passwd
#yum -y install --disablerepo=* --enablerepo=juno_install_repo --enablerepo=contrail_install_repo openstack-nova python-novaclient
yum -y install --disablerepo=* --enablerepo=${REPO_SERVERS} gnutls-utils
yum -y install --disablerepo=* --enablerepo=${REPO_SERVERS} openstack-nova python-novaclient
[[ ! -d /etc/nova/ ]] && { mkdir -p /etc/nova/; chown nova:nova /etc/nova; }
[ -f ./nova/nova.conf.controller ] && cp -p ./nova/nova.conf.controller /etc/nova/nova.conf
[ -f ./nova/api-paste.ini.controller ] && cp -p ./nova/api-paste.ini.controller /etc/nova/api-paste.ini
sed -i "s/nova_keystone_password/$NOVA_KSPASS/g" /etc/nova/nova.conf
sed -i "s/neutron_keystone_password/$NEUTRON_KSPASS/g" /etc/nova/nova.conf
sed -i "s/nova_db_password/$NOVA_DBPASS/g" /etc/nova/nova.conf
sed -i "s/contrail_controller/${openstack_controller}/g" /etc/nova/nova.conf
sed -i "s/openstack_controller/${openstack_controller}/g" /etc/nova/nova.conf
sed -i "s/local_controller/${local_controller}/g" /etc/nova/nova.conf
sed -i "s/http_cmd/${HTTP_CMD}/g" /etc/nova/nova.conf
sed -i "s/openstack_controller/${openstack_controller}/g" /etc/nova/api-paste.ini
sed -i "s/http_cmd/${HTTP_CMD}/g" /etc/nova/api-paste.ini
chown -R nova:nova /etc/nova
#openstack-config --set /etc/nova/nova.conf DEFAULT osapi_compute_listen_port  8775
if [[ ${local_controller} == ${local_controller} ]]; then
	#/usr/bin/openstack-db --yes --drop --rootpw ${MYSQL_ROOT_PASS} --service nova 
	[[ ! -z `mysql -uroot -p${MYSQL_ROOT_PASS} -qfsBe "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='nova'"` ]] &&  mysql -uroot -p${MYSQL_ROOT_PASS} -qfsBe "drop database nova"
mysql -uroot -p${MYSQL_ROOT_PASS}  << EOF
create database nova;
grant all on nova.* to nova@localhost identified by '$NOVA_DBPASS';
grant all on nova.* to nova@'$HOSTNAME' identified by '$NOVA_DBPASS';
grant all on nova.* to nova@'%' identified by '$NOVA_DBPASS';
EOF
	/usr/bin/nova-manage db sync
	#/usr/bin/openstack-db --init --service nova --password $NOVA_DBPASS
	#[ -f ~/nova/nova.sql ] && mysql -u root -p ${MYSQL_ROOT_PASS < ~/nova/nova.sql
	if [ `${KEYSTONE_CMD} user-list| grep nova |wc -l` -lt 1 ]; then
		${KEYSTONE_CMD} user-create --name=nova --pass=$NOVA_KSPASS --email=nova@${this_domain}
		${KEYSTONE_CMD} user-role-add --user=nova --tenant=service --role=admin
	fi
	[ `${KEYSTONE_CMD} service-list| grep nova |wc -l` -lt 1 ] && ${KEYSTONE_CMD} service-create --name=nova --type=compute --description="Nova Compute service"
	endpoint_id=`${KEYSTONE_CMD} service-list| grep nova|awk '{print $2}'`
	${KEYSTONE_CMD} endpoint-list| grep $endpoint_id| awk '{print $2}'| while read aabb
	do
		${KEYSTONE_CMD} endpoint-delete $aabb
	done
	[ `${KEYSTONE_CMD} endpoint-list| grep $endpoint_id |wc -l` -lt 1 ] && ${KEYSTONE_CMD} endpoint-create --service-id=`${KEYSTONE_CMD} service-list| grep nova| awk '{print $2}'` --publicurl="${HTTP_CMD}://${openstack_controller}:8774/v2/%(tenant_id)s" --internalurl="${HTTP_CMD}://${openstack_controller}:8774/v2/%(tenant_id)s" --adminurl="${HTTP_CMD}://${openstack_controller}:8774/v2/%(tenant_id)s"

fi

###
# SSL for Keystone
###
if [[ ${HTTP_CMD} == "https" ]]; then
	## Those might caused glance auth error
#	[[ -f nova/auth_token.py ]] && /bin/cp -pf  nova/auth_token.py /usr/lib/python2.6/site-packages/keystoneclient/middleware/auth_token.py
#	[[ -f nova/greenio.py ]] && /bin/cp -pf  nova/greenio.py /usr/lib/python2.6/site-packages/eventlet/greenio.py
	openstack-config --set /etc/nova/nova.conf keystone_authtoken insecure True
fi

#service rabbitmq-server restart
#service keepalived restart
#service haproxy restart
#service openstack-nova-api restart
#service openstack-nova-cert restart
#service openstack-nova-consoleauth restart 
#service openstack-nova-scheduler restart 
#service openstack-nova-conductor restart 
#service openstack-nova-novncproxy restart 
chkconfig openstack-nova-api on
chkconfig openstack-nova-cert on
chkconfig openstack-nova-consoleauth on 
chkconfig openstack-nova-scheduler on
chkconfig openstack-nova-conductor on
chkconfig openstack-nova-novncproxy on
