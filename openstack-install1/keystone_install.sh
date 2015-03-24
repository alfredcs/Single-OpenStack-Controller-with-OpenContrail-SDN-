#!/bin/bash
set -x
function usage() {
cat <<EOF
usage: $0 options

This script will install Keystone on a Openstack controller

Example:
        keystone_install.sh [-L] -v openstack_controller_vip [-r repo_names]

OPTIONS:
  -h -- Help Show this message
  -L -- With SSL
  -r -- Repo names
  -t -- Keystone admin token
  -V -- Verbose Verbose output
  -v -- VIP of the openstack controller

EOF
}
service_running() {
    [[ `uname -r` =~ ^2\. ]] && service $1 status >/dev/null
    [[ `uname -r` =~ ^3\. ]] && systemctl status $1 > /dev/null
}
first_openstack_controller=""
KEYSTONE_CMD=keystone
HTTP_CMD=http
[[ `id -u` -ne 0 ]] && { echo  "Must be root!"; exit 0; }
[[ $# -lt 2 ]] && { usage; exit 1; }
while getopts "hLr:t:v:VD" OPTION; do
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
t)
	KEYSTONE_DBPASS="$OPTARG"
	;;
v)
        controller="$OPTARG"
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

host_name=`echo $HOSTNAME | cut -d\. -f1|head -1`
local_controller=`egrep ${host_name} /etc/hosts|grep -v ^#|head -1|awk '{print $1}'`
first_openstack_controller=${local_controller}
if [[  ${first_openstack_controller} == ${local_controller}  ]]; then
	echo "Installing Keystone on the first Openstack controller node ......"
else
	###
        # Get Keys
        ###
        #[[ -f .keystone_grants ]] && { rm -rf .keystone_grants; rm -rf keystone_grants.enc; }
        #curl --insecure -o keystone_grants.enc https://${first_openstack_controller}/.tmp/keystone_grants.enc
        #[[  -f keystone/newkey.pem && -f keystone_grants.enc ]] && openssl rsautl -decrypt -inkey keystone/newkey.pem -in keystone_grants.enc -out .keystone_grants
        [[ ! -s  ./.keystone_grants ]] && { echo "Require credential file from Openstacl installation!"; exit 1; }
fi

ADMIN_KSPASS=${ADMIN_KSPASS:-`cat ./.keystone_grants|grep -i ADMIN_KSPASS| grep -v ^#|cut -d= -f2`}
KEYSTONE_DBPASS=${KEYSTONE_DBPASS:-`cat ./.keystone_grants|grep -i KEYSTONE_DBPASS| grep -v ^#|cut -d= -f2`}
MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS:-`cat ./.keystone_grants|grep -i MYSQL_ROOT_PASS| grep -v ^#|cut -d= -f2`}
ADMIN_TOKEN=${ADMIN_TOKEN:-`cat ./.keystone_grants|grep -i OS_SERVICE_TOKEN| grep -v ^#|cut -d= -f2`}
contAdmin_PASS=${contAdmin_PASS:-`cat ./.keystone_grants|grep -i contAdmin_PASS| grep -v ^#|cut -d= -f2`}
controller=${controller:-`cat ./.keystone_grants|grep -i openstack_controller| grep -v ^#|cut -d= -f2`}

domian_name=`uname -n|cut -d\. -f2,3,4,5`
#REPO_SERVER=${REPO_SERVER:-`cat ./.keystone_grants|grep -i REPO_SERVER| grep -v ^#|cut -d= -f2`}
[[ `uname -r` =~ ^3\. ]] && pkill keystone-all > /dev/null
[[ `uname -r` =~ ^2\. ]] && service openstak-keystone stop
#Install pkgs
[[ -d ./repos ]] && /bin/cp -fp ./repos/*.repo  /etc/yum.repos.d/.
#[[ ! -d /opt/repos/havana && `grep baseurl ./repos/havana_install.repo | grep -v ^#|grep file\:\/|wc -l` -gt 0 ]] && { mkdir -p /opt/repos; mount -t nfs $REPO_SERVER:/opt/repos /opt/repos; }
[[ `rpm -qa | grep keystone|wc -l` -gt 0 ]] && rpm -e --nodeps `rpm -qa|grep keystone`
[[ `rpm -qa | egrep -i 'percona|mysql'|wc -l` -gt 0 ]] && { service mysql stop --wsrep-cluster-address="gcomm://"; kill -9 `ps -ef | grep -v grep|grep mysql | awk '{print $2}'`; rpm -e --nodeps `rpm -qa | grep -i percona`; rpm -e --nodeps `rpm -qa | grep -i mysql`; rm -rf /var/lib/mysql /var/run/mysqld /var/lock/subsys/mysqld; }
###
# Configure mysql
##
[[ -f mysql/my.cnf.controller ]] && /bin/cp -f  mysql/my.cnf.controller /etc/my.cnf
sed -i "s/first_openstack_controller/${first_openstack_controller}/" /etc/my.cnf
#sed -i "s/second_openstack_controller/${second_openstack_controller}/" /etc/my.cnf
#sed -i "s/third_openstack_controller/${third_openstack_controller}/" /etc/my.cnf
sed -i "s/this_hostname/${host_name}/" /etc/my.cnf
sed -i "s/this_ip/${local_controller}/" /etc/my.cnf
###
# Create temp dir
##
[[ `grep mysql /etc/passwd| wc -l` -lt 1 ]] && adduser mysql
for dir_name in /var/lib/mysql `cat /etc/my.cnf|grep tmpdir| grep -v ^#| cut -d= -f2`
do
	[[ ! -d ${dir_name} ]] && mkdir -p ${dir_name}
	chown -R mysql:mysql ${dir_name}
done
yum -y  --disablerepo=* --enablerepo=percona_install_repo --enablerepo=${REPO_SERVERS}  install  Percona-XtraDB-Cluster-server-56 Percona-XtraDB-Cluster-client-56 Percona-XtraDB-Cluster-galera-3 #Percona-Server-shared-56
[[ $? != 0 ]] && { echo "MySql install failed!"; exit 1; }
###
# Install keystone
###
[ `rpm -qa | grep keystone|wc -l` -lt 1 ] && { yum -y install --disablerepo=* --enablerepo=${REPO_SERVERS} openstack-keystone python-keystoneclient openstack-utils; [[ $? -gt 0 ]] && { echo "YUM installation failed!"; exit 1; } }
# Configure Keystone
[[ ! -d /var/log/keystone/ ]] && mkdir -p /var/log/keystone/
[[ -f ./keystone/keystone.conf.controller ]] && /bin/cp -pf ./keystone/keystone.conf.controller /etc/keystone/keystone.conf
sed -i 's/^admin_token/#admin_token/g' /etc/keystone/keystone.conf
sed -i 's/^connection/#connection/g' /etc/keystone/keystone.conf
sed -i '/mysql/d' /etc/keystone/keystone.conf
sed -i "/^servers/ s/local_controller/${local_controller}/" /etc/keystone/keystone.conf
openstack-config --set /etc/keystone/keystone.conf sql connection mysql://keystone:$KEYSTONE_DBPASS@${local_controller}/keystone
export OS_SERVICE_TOKEN=$ADMIN_TOKEN
export OS_SERVICE_ENDPOINT=${HTTP_CMD}://${local_controller}:35358/v2.0
echo "export OS_SERVICE_TOKEN=$ADMIN_TOKEN" > ~/keystonerc
echo "export OS_SERVICE_ENDPOINT=http://${local_controller}:35358/v2.0" >> ~/keystonerc
openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_token $ADMIN_TOKEN
###
# Add SSL
###
[[ -f ./keystone/server01.key ]] && /bin/cp -pf ./keystone/server01.key /etc/keystone/ssl/private/server01.key
[[ -f ./keystone/server01.crt ]] && /bin/cp -pf ./keystone/server01.crt /etc/keystone/ssl/certs/server01.crt
[[ -f ./keystone/ca.crt ]] && /bin/cp -pf ./keystone/ca.crt /etc/keystone/ssl/certs/ca.crt 
[[ -f ./keystone/ca.key ]] && /bin/cp -pf ./keystone/ca.key /etc/keystone/ssl/private/ca.key
[[ -f ./keystone/policy.json ]] && /bin/cp -pf ./keystone/policy.json /etc/keystone/policy.json
[[ -f ./keystone/keystone-paste.ini ]] && /bin/cp -pf ./keystone/keystone-paste.ini /etc/keystone/keystone-paste.ini
if [[ ${HTTP_CMD} == "https" ]]; then
	openstack-config --set /etc/keystone/keystone.conf  ssl enable true 
	openstack-config --set /etc/keystone/keystone.conf  ssl certfile /etc/keystone/ssl/certs/server01.crt
	openstack-config --set /etc/keystone/keystone.conf  ssl keyfile /etc/keystone/ssl/private/server01.key 
	openstack-config --set /etc/keystone/keystone.conf  ssl ca_certs /etc/keystone/ssl/certs/ca.crt
	openstack-config --set /etc/keystone/keystone.conf  ssl ca_key /etc/keystone/ssl/private/ca.key
	openstack-config --set /etc/keystone/keystone.conf  ssl cert_required  False
	openstack-config --set /etc/keystone/keystone.conf  token driver keystone.token.backends.memcache.Token
	openstack-config --set /etc/keystone/keystone.conf  token provider keystone.token.providers.pki.Provider
	openstack-config --set /etc/keystone/keystone.conf  token expiration 3600
	#openstack-config --set /etc/keystone/keystone.conf  DEFAULT public_endpoint ${HTTP_CMD}://${controller}:5000/
	#openstack-config --set /etc/keystone/keystone.conf  DEFAULT admin_endpoint ${HTTP_CMD}://${controller}:35357/
	openstack-config --set /etc/keystone/keystone.conf  DEFAULT public_port 5001
	openstack-config --set /etc/keystone/keystone.conf  DEFAULT admin_port 35358
else
	openstack-config --set /etc/keystone/keystone.conf  token driver keystone.token.persistence.backends.memcache.Token
	openstack-config --set /etc/keystone/keystone.conf  token provider  keystone.token.providers.uuid.Provider
	openstack-config --set /etc/keystone/keystone.conf  DEFAULT public_port 5001
	openstack-config --set /etc/keystone/keystone.conf  DEFAULT admin_port 35358
fi
keystone-manage pki_setup --keystone-user keystone --keystone-group keystone
[[ ! -d /etc/keystone/ssl/private/ ]] && mkfir -p /etc/keystone/ssl/private/
[[ ! -d /etc/keystone/ssl/certs/ ]] && mkfir -p /etc/keystone/ssl/cert2/
chown -R keystone:keystone /etc/keystone
chown -R keystone:keystone /var/log/keystone
chown -R keystone:keystone /etc/keystone/ssl
chmod -R o-rwx /etc/keystone/ssl
###
# Edit for CentOS 7 with Percona 5.6
###
setenforce 0
[[ -f /etc/selinux/config ]] && sed -i '/^SELINUX/ s/SELINUX.*/SELINUX=permissive' /etc/selinux/config
[[ `uname -r` =~ ^3\. ]] && systemctl start mysql@bootstrap.service
[[ `uname -r` =~ ^2\. ]] && service start mysql --wsrep-cluster-address="gcomm://"
#if ! service_running mysql; then
#	/usr/bin/mysql_install_db
#	if [[ ${local_controller} == ${first_openstack_controller} ]]; then
#		 systemctl start mysql@bootstrap.service
#	else
#        	systemctl restart mysql
#	fi
#	sleep 10
#fi

if [[ ${first_openstack_controller} == ${local_controller} ]] ; then
	/usr/bin/mysqladmin -u root password ${MYSQL_ROOT_PASS}
	#/usr/bin/mysqladmin -u root -h ${local_controller} password ${MYSQL_ROOT_PASS}
	#/usr/bin/mysqladmin -u root -h localhost password ${MYSQL_ROOT_PASS} -p${MYSQL_ROOT_PASS}
	sstuser_password=`cat mysql/my.cnf.controller | grep wsrep_sst_auth| cut -d: -f2|sed 's/\"$//'`
	echo "CREATE USER 'sstuser'@'localhost' IDENTIFIED BY '${sstuser_password}';" > /tmp/.wsrep
	echo "GRANT RELOAD, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'sstuser'@'localhost';" >> /tmp/.wsrep
	mysql -uroot -p${MYSQL_ROOT_PASS} < /tmp/.wsrep
	rm -f /tmp/.wsrep

	#echo "drop database keystone" > /tmp/.wsrep
	#mysql -uroot -p${MYSQL_ROOT_PASS} < /tmp/.wsrep
	#rm -f /tmp/.wsrep
	[[ ! -z `mysql -uroot -p${MYSQL_ROOT_PASS} -qfsBe "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='keystone'"` ]] &&  mysql -uroot -p${MYSQL_ROOT_PASS} -qfsBe "drop database keystone"
	##
	# Temp fix for backward compactible
	##
	#[[ ! -f /usr/lib64/libmysqlclient_r.so.16 ]] && ln -sf `find /usr/lib64 -maxdepth 1 \!  -type l  -exec ls -d {} +| grep libmysqlclient.so` /usr/lib64/libmysqlclient_r.so.16
	#/usr/bin/openstack-db --drop --yes --rootpw ${MYSQL_ROOT_PASS} --service keystone
	#/usr/bin/openstack-db --init --service keystone --password $KEYSTONE_DBPASS
	echo "create database keystone;" > /tmp/._keystone.sql
	echo "grant all on keystone.* to keystone@'%' identified by '$KEYSTONE_DBPASS';" >> /tmp/._keystone.sql
	echo "grant all on keystone.* to keystone@'localhost' identified by '$KEYSTONE_DBPASS';" >> /tmp/._keystone.sql
	echo "grant all on keystone.* to keystone@'${local_controller}' identified by '$KEYSTONE_DBPASS';" >> /tmp/._keystone.sql
	mysql -uroot -p${MYSQL_ROOT_PASS} < /tmp/._keystone.sql
	/bin/sh -c "keystone-manage db_sync" keystone
	if [[ $? -ne 0 ]]; then
		[[ `uname -r` =~ ^3\. ]] && systemctl stop mysql@bootstrap.service
		[[ `uname -r` =~ ^2\. ]] && service mysql start --wsrep-cluster-address="gcomm://"
		pkill mysqld
		/usr/bin/mysql_install_db
		if [[ ${local_controller} == ${local_controller} ]]; then
			[[ `uname -r` =~ ^3\. ]] && systemctl start mysql@bootstrap.service
			[[ `uname -r` =~ ^2\. ]] && service mysql start --wsrep-cluster-address="gcomm://"
			
		else
        		[[ `uname -r` =~ ^3\. ]] && syetemctl restart mysql
        		[[ `uname -r` =~ ^2\. ]] && service mysql start --wsrep-cluster-address="gcomm://"
		fi
		#if  ! service_running mysql; then
       		#	echo "Mysql is not running!"
        	#	exit 1
		#fi
		/usr/bin/mysqladmin -u root password ${MYSQL_ROOT_PASS}
		/usr/bin/mysqladmin -u root -h ${local_controller} password ${MYSQL_ROOT_PASS}
		/usr/bin/mysqladmin -u root -h localhost password ${MYSQL_ROOT_PASS} -p${MYSQL_ROOT_PASS}
		mysql -uroot -p${MYSQL_ROOT_PASS} < /tmp/._keystone.sql
		/bin/sh -c "keystone-manage db_sync" keystone
		[[ $? -ne 0 ]] && { echo "Keystone DB initialization failed"; exit 1; }
	fi
fi
###
# Set Mysql root password
###
#/usr/bin/mysqladmin -u root password ${MYSQL_ROOT_PASS}
#/usr/bin/mysqladmin -u root -h $controller password ${MYSQL_ROOT_PASS}
#/usr/bin/mysqladmin -u root -h localhost  password ${MYSQL_ROOT_PASS}
chown -R keystone:keystone /etc/keystone/* /var/log/keystone/keystone.log
#systemctl enable openstack-keystone.service
#systemctl start openstack-keystone.service
[[ `uname -r` =~ ^3\. ]] &&  nohup /usr/bin/keystone-all > /dev/null 2>&1 &
[[ `uname -r` =~ ^2\. ]] &&  { service memcached restart; service openstack-keystone start; }
[[ $? -ne 0 ]] && exit 1
sleep 2

### Create tenants
if [[ $first_openstack_controller == ${local_controller} ]] ; then
	${KEYSTONE_CMD} tenant-create --name=admin --description="Admin Tenant"
	${KEYSTONE_CMD} tenant-create --name=service --description="Service Tenant"
	${KEYSTONE_CMD} tenant-create --name=contrail --description="Contrail SDN Project"
	${KEYSTONE_CMD} user-create --name=admin --pass=${ADMIN_KSPASS} --email=admin@$domian_name
	${KEYSTONE_CMD} user-create --name=contAdmin --pass=${contAdmin_PASS} --email=contadmin@$domian_name
	${KEYSTONE_CMD} role-create --name=admin
	${KEYSTONE_CMD} role-create --name=Member
#	${KEYSTONE_CMD} user-role-add --user-id=`${KEYSTONE_CMD} user-list| grep admin| awk '{print $2}'` --tenant-id=`${KEYSTONE_CMD} tenant-list| grep admin| awk '{print $2}'` 
	${KEYSTONE_CMD} user-role-add --user contAdmin --role-id admin  --tenant `${KEYSTONE_CMD} tenant-list| grep contrail| awk '{print $2}'`
	${KEYSTONE_CMD} user-role-add --user admin --role-id admin  --tenant `${KEYSTONE_CMD} tenant-list| grep admin| awk '{print $2}'`
	${KEYSTONE_CMD} service-create --name=keystone --type=identity  --description="Keystone Identity Service"
	${KEYSTONE_CMD} service-create --name=glance --type=image  --description="Glance Image Service"
	${KEYSTONE_CMD} service-create --name=nova --type=compute --description="Nova Compute Service"
	${KEYSTONE_CMD} service-create --name=neutron --type=network  --description="Openstack Networking Service"
	KEYSTONE_ID=`${KEYSTONE_CMD} service-list|grep keystone|awk '{print $2}'`
	${KEYSTONE_CMD} endpoint-create --service-id=$KEYSTONE_ID --publicurl=${HTTP_CMD}://$controller:5000/v2.0 \
        	--internalurl=${HTTP_CMD}://$controller:5000/v2.0 --adminurl=${HTTP_CMD}://$controller:35357/v2.0
	${KEYSTONE_CMD} user-password-update --pass=${ADMIN_KSPASS} admin
	${KEYSTONE_CMD} user-password-update --pass=${contAdmin_PASS} contAdmin
fi
echo "export OS_USERNAME=contAdmin" > ~/contrc
echo "export OS_PASSWORD=${contAdmin_PASS}" >> ~/contrc
echo "export OS_TENANT_NAME=contrail" >>~/contrc
echo "export OS_IMAGE_API_VERSION=1" >>~/contrc
echo "export OS_AUTH_URL=${HTTP_CMD}://$controller:35357/v2.0" >>~/contrc
