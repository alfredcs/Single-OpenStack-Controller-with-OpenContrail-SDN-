#!/bin/bash
set -x
function usage() {
cat <<EOF
usage: $0 options

This script will Horizon on a Openstack controller

Example:
        horizon_install.sh [-L] -v openstack_controller_vip -r REPO_SERVERS

OPTIONS:
  -h -- Help Show this message
  -L -- SSL for Keystone
  -r -- Repo names ie.e. repo1,repo2,repo3
  -S -- The second contrail controller's IP addressd
  -V -- Verbose Verbose output
  -v -- VIP of the openstack controller

EOF
}
HTTP_CMD=http
[[ `id -u` -ne 0 ]] && { echo  "Must be root!"; exit 0; }
while getopts "hLv:r:VD" OPTION; do
case "$OPTION" in
h)
        usage
        exit 0
        ;;
L)
	HTTP_CMD="https"
	;;
v)
        openstack_controller="$OPTARG"
        ;;
r)
	REPO_SERVERS="$OPTARG"
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

local_controller=`egrep $HOSTNAME /etc/hosts|grep -v ^#|awk '{print $1}'`
if [[  ${local_controller} == ${local_controller}  ]]; then
        echo "Installing Glance on the firsth Openstack controller node ......"
else
        ###
        # Get Keys
        ###
        #[[ -f .keystone_grants ]] && { rm -rf .keystone_grants; rm -rf eystone_grants.enc; }
        #curl --insecure -o keystone_grants.enc https://${first_openstack_controller}/.tmp/keystone_grants.enc
        #[[  -f keystone/newkey.pem && -f keystone_grants.enc ]] && openssl rsautl -decrypt -inkey keystone/newkey.pem -in keystone_grants.enc -out .keystone_grants
        [[ ! -f  ./.keystone_grants ]] && { echo "Require credential file from Openstacl installation!"; exit 1; }
fi

openstack_controller=${openstack_controller:-`cat ./.keystone_grants|grep -i openstack_controller| grep -v ^#|cut -d= -f2`}

[[ `rpm -qa | grep openstack-dashboard|wc -l` -gt 0 ]] && rpm -e --nodeps `rpm -qa|egrep 'mod_ssl|mod_wsgi|openstack-dashboard|python-django-openstack-auth'`
yum clena all
yum -y install --disablerepo=* --enablerepo=`echo ${REPO_SERVERS}|sed 's/contrail.*\,//' | sed 's/\,contrail.*//'` openstack-dashboard mod_wsgi mod_ssl python-django-openstack-auth
[[ -f horizon/local_settings.controller ]] && /bin/cp -fp horizon/local_settings.controller /etc/openstack-dashboard/local_settings
[[ -f horizon/openstack-dashboard.conf.controller && ${HTTP_CMD}=="http" ]] && /bin/cp -fp horizon/openstack-dashboard.conf.controller /etc/httpd/conf.d/openstack-dashboard.conf
[[ -f horizon/openstack-dashboard.ssl.conf.controller && ${HTTP_CMD}=="https" ]] && /bin/cp -fp horizon/openstack-dashboard.ssl.conf.controller /etc/httpd/conf.d/openstack-dashboard.conf
sed -i "s/controller/${openstack_controller}/g" /etc/openstack-dashboard/local_settings
sed -i "s/controller/${openstack_controller}/g" /etc/httpd/conf.d/openstack-dashboard.conf
sed -i "s/http_cmd/${HTTP_CMD}/g" /etc/openstack-dashboard/local_settings
chkconfig memcached on
chkconfig httpd on
service memcached restart
service httpd restart
