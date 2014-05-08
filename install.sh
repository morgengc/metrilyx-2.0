#!/usr/bin/env bash

INSTALL_ROOT="/opt";
INSTALL_TIME=$(date '+%d%b%Y_%H%M%S');
APP_HOME="${INSTALL_ROOT}/metrilyx";

if [[ -f "/etc/redhat-release" ]]; then
	HTTPD="httpd"
	HTTP_USER="apache"
	PKGS="libuuid gcc uuid ${HTTPD} mod_wsgi python-setuptools python-devel mongo-10gen mongo-10gen-server"
	PKG_INSTALLER="yum -y install"
	PKG_LISTER="rpm -qa"
	PKG_S_PREFIX="^"
elif [[ -f "/etc/debian_version" ]]; then
	HTTPD="apache2"
	HTTP_USER="www-data"
	PKGS="libuuid1 gcc uuid ${HTTPD} libapache2-mod-wsgi python-setuptools python-dev mongodb mongodb-server"
	PKG_INSTALLER="apt-get install -y"
	PKG_LISTER="dpkg -l"
	PKG_S_PREFIX="ii\s+"
else
	echo "Currently only RedHat/Debian based distro are supported.  Please install manually.";
	exit 1;
fi

clean() {
	find . -name '*.pyc' -exec rm -rvf '{}' \;
}
setup_app_dirs() {
	mkdir -p ${APP_HOME};
	cp -a . ${APP_HOME}/;
	chmod g+w ${APP_HOME};
	( id celery 2>&1 ) > /dev/null || useradd celery;
	chgrp celery ${APP_HOME};
}
setup_celery_startup() {
	cp -a etc/rc.d/init.d/* /etc/rc.d/init.d/;
	if [ ! -f /etc/sysconfig/celeryd ]; then 
		cp etc/sysconfig/celeryd /etc/sysconfig/;
	fi	
}

install_pydeps() {
	echo "-- Installing python dependencies..."
	which pip || easy_install pip;
	for pypkg in $(cat PYPACKAGES); do
		pip list | grep ${pypkg} || pip install ${pypkg};
	done;
}

backup_curr_install() {
	clean;
	if [ -d "${INSTALL_ROOT}/metrilyx" ]; then
		echo "- Backing up existing installation...";
		mv ${APP_HOME} ${APP_HOME}-${INSTALL_TIME};
	fi;
}
setup_app_config() {
	if [ -f "/opt/metrilyx-${INSTALL_TIME}/etc/metrilyx/metrilyx.conf" ]; then
		echo "- Importing existing data..."
		echo "  configs...";
		cp ${APP_HOME}-${INSTALL_TIME}/etc/metrilyx/metrilyx.conf ${APP_HOME}/etc/metrilyx/metrilyx.conf;
		if [ -f "${APP_HOME}-${INSTALL_TIME}/metrilyx/static/config.js" ]; then
			cp ${APP_HOME}-${INSTALL_TIME}/metrilyx/static/config.js ${APP_HOME}/metrilyx/static/config.js;
		fi
		if [ ! -f "${APP_HOME}/metrilyx/static/config.js" ]; then
			cp ${APP_HOME}/metrilyx/static/config.js.sample ${APP_HOME}/metrilyx/static/config.js;
		fi
		echo "  dashboards..."
		cp -a ${APP_HOME}-${INSTALL_TIME}/pagemodels ${APP_HOME}/;
		echo "  heatmaps..."
		cp -a ${APP_HOME}-${INSTALL_TIME}/heatmaps ${APP_HOME}/;
	else
		cp ${APP_HOME}/metrilyx/static/config.js.sample ${APP_HOME}/metrilyx/static/config.js;
		cp etc/metrilyx/metrilyx.conf.sample ${APP_HOME}/etc/metrilyx/metrilyx.conf;
		${EDITOR:-vi} ${APP_HOME}/etc/metrilyx/metrilyx.conf;
	fi
}
install_app(){
	echo "- Installing app..."
	setup_app_dirs;
	setup_app_config;
	
}
app_postinstall() {
	if [[ -f "/etc/redhat-release" ]]; then
		setup_celery_startup;
	fi
	# apache restart
}
configure_apache() {
	echo "- Installing web components..."
	if [[ -f "/etc/debian_version" ]]; then
		cp etc/httpd/conf.d/metrilyx.conf /etc/apache2/sites-available/ && rm /etc/apache2/sites-enabled/*.conf && a2ensite metrilyx;
		sed -i "s/#Require all granted/Require all granted/g" /etc/apache2/sites-available/metrilyx.conf;
		a2enmod rewrite;
		a2enmod headers;
	elif [[ -f "/etc/redhat-release" ]]; then
		cp etc/httpd/conf.d/metrilyx.conf /etc/httpd/conf.d/;
		chown -R $HTTP_USER ${APP_HOME};
	fi
}
init_postgres() {
	/etc/init.d/postgresql-9.3 initdb;
	/etc/init.d/postgresql-9.3 start;
	chkconfig postgresql-9.3 on;
}
init_django() {
	cd ${APP_HOME};
	echo "- Removing current db data..."
	rm -rf ./metrilyx.sqlite3 ./celerybeat-schedule.db;
	python ./manage.py syncdb;
	python ./manage.py createinitialrevisions;
	[[ -f "./metrilyx.sqlite3" ]] && chown ${HTTP_USER}:${HTTP_USER} ./metrilyx.sqlite3;
	# apache restart
}
##### Main ####

if [ "$(whoami)" != "root" ]; then
	echo "Must be root!";
	exit 1;
fi

if [ "$1" == "all" ]; then
	install_pydeps;
	backup_curr_install;
	install_app;
	configure_apache;
	app_postinstall;
	echo "(todo): Install and init postgres"
	#init_postgres && init_django;
	# apache restart
elif [ "$1" == "app" ]; then
	install_pydeps;
	backup_curr_install;
	install_app;
	configure_apache;
	app_postinstall;
else
	echo "Executing $1...";
	$1;
fi


echo ""
echo " ** Heatmaps are still in beta phase, currently requiring a frequent restart."
echo " ** If you choose to use heatmaps set the config options"
echo " ** (/opt/metrilyx/etc/metrilyx/metrilyx.conf) and start celerybeat and celeryd."
echo ""

