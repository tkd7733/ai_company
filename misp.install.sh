#!/bin/bash

export RUN_PHP='/usr/bin/scl enable rh-php71 '
export RUN_PYTHON='/usr/bin/scl enable rh-python36 '
export PATH_TO_MISP='/var/www/MISP'
export CAKE="$PATH_TO_MISP/app/Console/cake"
export MISP_BASEURL=''
export MISP_LIVE='1'
export DBHOST='localhost'
export DBNAME='misp'
export DBUSER_ADMIN='root'
export DBPASSWORD_ADMIN="$(openssl rand -hex 32)"
export DBUSER_MISP='misp'
export DBPASSWORD_MISP="$(openssl rand -hex 32)"
export FQDN='localhost'
export OPENSSL_CN='Common Name'
export OPENSSL_C='LU'
export OPENSSL_ST='State'
export OPENSSL_L='Location'
export OPENSSL_O='Organization'
export OPENSSL_OU='Organizational Unit'
export OPENSSL_EMAILADDRESS='info@localhost'
export GPG_REAL_NAME='Autogenerated Key'
export GPG_COMMENT='WARNING: MISP AutoGenerated Key consider this Key VOID!'
export GPG_EMAIL_ADDRESS='admin@admin.test'
export GPG_KEY_LENGTH='2048'
export GPG_PASSPHRASE='Password1234'
export PHP_INI=/etc/opt/rh/rh-php71/php.ini

echo "Admin (root) DB Password: $DBPASSWORD_ADMIN"
echo "User  (misp) DB Password: $DBPASSWORD_MISP"

#######################################################################
#                    MISP CENTOS7 INSTALL SCRIPT                      #
#                                                                     #
# Revised from:                                                       #
# https://github.com/MISP/MISP/blob/2.4/INSTALL/xINSTALL.centos7.txt  #
#                                                                     #
# > Must be run as root                                               #
# > Make sure you source misp.variables.sh (seperate) first           #
#######################################################################

# Set hostname
hostnamectl set-hostname misp.local

# system update
yum update -y

# install epel
yum install epel-release -y

# install firewalld
yum install firewalld

# enable and start firewalld
systemctl enable firewalld.service
systemctl start  firewalld.service

# Since MISP 2.4 PHP 5.5 is a minimal requirement, so we need a newer version than CentOS base provides
# Software Collections is a way do to this, see https://wiki.centos.org/AdditionalResources/Repositories/SCL
yum install centos-release-scl -y

# Install the dependencies
yum install gcc git httpd zip redis mariadb mariadb-server python-devel python-pip python-zmq libxslt-devel zlib-devel -y

# Install PHP 7.1 from SCL, see https://www.softwarecollections.org/en/scls/rhscl/rh-php71/
yum install rh-php71 rh-php71-php-fpm rh-php71-php-devel rh-php71-php-mysqlnd rh-php71-php-mbstring rh-php71-php-xml rh-php71-php-bcmath rh-php71-php-opcache -y

# Install Python 3.6 from SCL, see
# https://www.softwarecollections.org/en/scls/rhscl/rh-python36/
yum install rh-python36 -y

# rh-php71-php only provided mod_php for httpd24-httpd from SCL
# if we want to use httpd from CentOS base we can use rh-php71-php-fpm instead
systemctl enable rh-php71-php-fpm.service
systemctl start  rh-php71-php-fpm.service

/usr/bin/scl enable rh-php71 "pear channel-update pear.php.net"
/usr/bin/scl enable rh-php71 "pear install Crypt_GPG"    # we need version >1.3.0

# GPG needs lots of entropy, haveged provides entropy
yum install haveged -y
systemctl enable haveged.service
systemctl start  haveged.service

# Enable and start redis
systemctl enable redis.service
systemctl start  redis.service

# Download MISP using git in the /var/www/ directory.
cd /var/www/
git clone https://github.com/MISP/MISP.git
cd /var/www/MISP
git checkout tags/$(git describe --tags `git rev-list --tags --max-count=1`)

# Make git ignore filesystem permission differences
git config core.filemode false

# Fetch submodules
cd /var/www/MISP
git submodule update --init --recursive
# Make git ignore filesystem permission differences for submodules
git submodule foreach --recursive git config core.filemode false

# install Mitre's STIX and its dependencies by running the following commands:
yum install python-importlib python-lxml python-dateutil python-six -y
cd /var/www/MISP/app/files/scripts
git clone https://github.com/CybOXProject/python-cybox.git
git clone https://github.com/STIXProject/python-stix.git
cd /var/www/MISP/app/files/scripts/python-cybox
git config core.filemode false
# If you umask is has been changed from the default, it is a good idea to reset it to 0022 before installing python modules
UMASK=$(umask)
umask 0022
/usr/bin/scl enable rh-python36 "python3 setup.py install"
cd /var/www/MISP/app/files/scripts/python-stix
git config core.filemode false
/usr/bin/scl enable rh-python36 "python3 setup.py install"

# install maec
/usr/bin/scl enable rh-python36 "pip install maec"

# install zmq
/usr/bin/scl enable rh-python36 "pip install zmq"

# install redis
/usr/bin/scl enable rh-python36 "pip install redis"

# install mixbox to accomodate the new STIX dependencies:
cd /var/www/MISP/app/files/scripts/
git clone https://github.com/CybOXProject/mixbox.git
cd /var/www/MISP/app/files/scripts/mixbox
git config core.filemode false
/usr/bin/scl enable rh-python36 "python3 setup.py install"

# install PyMISP
cd /var/www/MISP/PyMISP
/usr/bin/scl enable rh-python36 "python3 setup.py install"

# Enable python3 for php-fpm
echo 'source scl_source enable rh-python36' | tee -a /etc/opt/rh/rh-php71/sysconfig/php-fpm
sed -i.org -e 's/^;\(clear_env = no\)/\1/' /etc/opt/rh/rh-php71/php-fpm.d/www.conf
systemctl restart rh-php71-php-fpm.service

umask $UMASK


# CakePHP is now included as a submodule of MISP and has been fetch by a previous step.
# Install CakeResque along with its dependencies if you intend to use the built in background jobs:
chown -R apache:apache /var/www/MISP
mkdir /usr/share/httpd/.composer
chown apache:apache /usr/share/httpd/.composer
cd /var/www/MISP/app
sudo -u apache /usr/bin/scl enable rh-php71 "php composer.phar require kamisama/cake-resque:4.1.2"
sudo -u apache /usr/bin/scl enable rh-php71 "php composer.phar config vendor-dir Vendor"
sudo -u apache /usr/bin/scl enable rh-php71 "php composer.phar install"

# CakeResque normally uses phpredis to connect to redis, but it has a (buggy) fallback connector through Redisent. It is highly advised to install phpredis using "yum install php-redis"
/usr/bin/scl enable rh-php71 "pecl install redis-2.2.8"
echo "extension=redis.so" | tee /etc/opt/rh/rh-php71/php-fpm.d/redis.ini
ln -s ../php-fpm.d/redis.ini /etc/opt/rh/rh-php71/php.d/99-redis.ini
systemctl restart rh-php71-php-fpm.service

# If you have not yet set a timezone in php.ini
echo 'date.timezone = "Europe/London"' | tee /etc/opt/rh/rh-php71/php-fpm.d/timezone.ini
ln -s ../php-fpm.d/timezone.ini /etc/opt/rh/rh-php71/php.d/99-timezone.ini

# Recommended: Change some PHP settings in /etc/opt/rh/rh-php71/php.ini
export max_execution_time='300'
export memory_limit='512M'
export upload_max_filesize='50M'
export post_max_size='50M'
for key in upload_max_filesize post_max_size max_execution_time max_input_time memory_limit
do
    sed -i "s/^\($key\).*/\1 = $(eval echo \${$key})/" $PHP_INI
done
systemctl restart rh-php71-php-fpm.service

# To use the scheduler worker for scheduled tasks, do the following:
cp -fa /var/www/MISP/INSTALL/setup/config.php /var/www/MISP/app/Plugin/CakeResque/Config/config.php

# Make sure the permissions are set correctly using the following commands as root:
chown -R root:apache /var/www/MISP
find /var/www/MISP -type d -exec chmod g=rx {} \;
chmod -R g+r,o= /var/www/MISP
chmod -R 750 /var/www/MISP
chmod -R g+ws /var/www/MISP/app/tmp
chmod -R g+ws /var/www/MISP/app/files
chmod -R g+ws /var/www/MISP/app/files/scripts/tmp
chown apache:apache /var/www/MISP/app/files
chown apache:apache /var/www/MISP/app/files/terms
chown apache:apache /var/www/MISP/app/files/scripts/tmp
chown apache:apache /var/www/MISP/app/Plugin/CakeResque/tmp
chown -R apache:apache /var/www/MISP/app/Config
chown -R apache:apache /var/www/MISP/app/tmp
chown -R apache:apache /var/www/MISP/app/webroot/img/orgs
chown -R apache:apache /var/www/MISP/app/webroot/img/custom

# Enable, start and secure your mysql database server
systemctl enable mariadb.service
systemctl start  mariadb.service

echo "Admin (root) DB Password: $DBPASSWORD_ADMIN"
echo "User  (misp) DB Password: $DBPASSWORD_MISP"

# If you want to continue copy pasting set the MySQL root password to $DBPASSWORD_ADMIN
echo $DBPASSWORD_ADMIN
mysql_secure_installation

# Additionally, it is probably a good idea to make the database server listen on localhost only
echo [mysqld] | tee /etc/my.cnf.d/bind-address.cnf
echo bind-address=127.0.0.1 | tee -a /etc/my.cnf.d/bind-address.cnf
systemctl restart mariadb.service

# create database stuff
mysql -u $DBUSER_ADMIN -p$DBPASSWORD_ADMIN -e "create database $DBNAME;"
mysql -u $DBUSER_ADMIN -p$DBPASSWORD_ADMIN -e "grant usage on *.* to $DBNAME@localhost identified by '$DBPASSWORD_MISP';"
mysql -u $DBUSER_ADMIN -p$DBPASSWORD_ADMIN -e "grant all privileges on $DBNAME.* to '$DBUSER_MISP'@'localhost';"
mysql -u $DBUSER_ADMIN -p$DBPASSWORD_ADMIN -e "flush privileges;"

# Import the empty MySQL database from MYSQL.sql
sudo -u apache cat $PATH_TO_MISP/INSTALL/MYSQL.sql | mysql -u $DBUSER_MISP -p$DBPASSWORD_MISP $DBNAME

# Now configure your apache server with the DocumentRoot /var/www/MISP/app/webroot/
cp /var/www/MISP/INSTALL/apache.misp.centos7 /etc/httpd/conf.d/misp.conf

# Since SELinux is enabled, we need to allow httpd to write to certain directories
chcon -t httpd_sys_rw_content_t /var/www/MISP/app/files
chcon -t httpd_sys_rw_content_t /var/www/MISP/app/files/terms
chcon -t httpd_sys_rw_content_t /var/www/MISP/app/files/scripts/tmp
chcon -t httpd_sys_rw_content_t /var/www/MISP/app/Plugin/CakeResque/tmp
chcon -R -t httpd_sys_rw_content_t /var/www/MISP/app/tmp
chcon -R -t httpd_sys_rw_content_t /var/www/MISP/app/tmp/logs
chcon -R -t httpd_sys_rw_content_t /var/www/MISP/app/webroot/img/orgs
chcon -R -t httpd_sys_rw_content_t /var/www/MISP/app/webroot/img/custom

# Revise all permissions so update in Web UI works.
chcon -R -t httpd_sys_rw_content_t /var/www/MISP/app/tmp


# Allow httpd to connect to the redis server and php-fpm over tcp/ip
setsebool -P httpd_can_network_connect on

# Enable and start the httpd service
systemctl enable httpd.service
systemctl start  httpd.service

# Open a hole in the iptables firewall
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --reload


# MISP saves the stdout and stderr of it's workers in /var/www/MISP/app/tmp/logs
# To rotate these logs install the supplied logrotate script:

cp $PATH_TO_MISP/INSTALL/misp.logrotate /etc/logrotate.d/misp
chmod 0640 /etc/logrotate.d/misp

# Now make logrotate work under SELinux as well
# Allow logrotate to modify the log files
semanage fcontext -a -t httpd_log_t "/var/www/MISP/app/tmp/logs(/.*)?"
chcon -R -t httpd_log_t /var/www/MISP/app/tmp/logs

# Allow logrotate to read /var/www
checkmodule -M -m -o /tmp/misplogrotate.mod $PATH_TO_MISP/INSTALL/misplogrotate.te
semodule_package -o /tmp/misplogrotate.pp -m /tmp/misplogrotate.mod
semodule -i /tmp/misplogrotate.pp


# There are 4 sample configuration files in $PATH_TO_MISP/app/Config that need to be copied
sudo -u apache cp -a $PATH_TO_MISP/app/Config/bootstrap.default.php $PATH_TO_MISP/app/Config/bootstrap.php
sudo -u apache cp -a $PATH_TO_MISP/app/Config/database.default.php $PATH_TO_MISP/app/Config/database.php
sudo -u apache cp -a $PATH_TO_MISP/app/Config/core.default.php $PATH_TO_MISP/app/Config/core.php
sudo -u apache cp -a $PATH_TO_MISP/app/Config/config.default.php $PATH_TO_MISP/app/Config/config.php

echo "<?php
class DATABASE_CONFIG {
        public \$default = array(
                'datasource' => 'Database/Mysql',
                //'datasource' => 'Database/Postgres',
                'persistent' => false,
                'host' => '$DBHOST',
                'login' => '$DBUSER_MISP',
                'port' => 3306, // MySQL & MariaDB
                //'port' => 5432, // PostgreSQL
                'password' => '$DBPASSWORD_MISP',
                'database' => '$DBNAME',
                'prefix' => '',
                'encoding' => 'utf8',
        );
}" | sudo -u apache tee $PATH_TO_MISP/app/Config/database.php

# Configure the fields in the newly created files:
# config.php   : baseurl (example: 'baseurl' => 'http://misp',) - don't use "localhost" it causes issues when browsing externally
# core.php   : Uncomment and set the timezone: `// date_default_timezone_set('UTC');`
# database.php : login, port, password, database
# DATABASE_CONFIG has to be filled
# With the default values provided in section 6, this would look like:
# class DATABASE_CONFIG {
#   public $default = array(
#       'datasource' => 'Database/Mysql',
#       'persistent' => false,
#       'host' => 'localhost',
#       'login' => 'misp', // grant usage on *.* to misp@localhost
#       'port' => 3306,
#       'password' => 'XXXXdbpasswordhereXXXXX', // identified by 'XXXXdbpasswordhereXXXXX';
#       'database' => 'misp', // create database misp;
#       'prefix' => '',
#       'encoding' => 'utf8',
#   );
#}
mv /var/www/MISP/app/vendor /var/www/MISP/app/Vendor
# Important! Change the salt key in /var/www/MISP/app/Config/config.php
# The admin user account will be generated on the first login, make sure that the salt is changed before you create that user
# If you forget to do this step, and you are still dealing with a fresh installation, just alter the salt,
# delete the user from mysql and log in again using the default admin credentials (admin@admin.test / admin)

# If you want to be able to change configuration parameters from the webinterface:
chown apache:apache /var/www/MISP/app/Config/config.php
chcon -t httpd_sys_rw_content_t /var/www/MISP/app/Config/config.php

# Set some MISP directives with the command line tool
/usr/bin/scl enable rh-php71 "$CAKE Live $MISP_LIVE"

# Change base url
/usr/bin/scl enable rh-php71 "$CAKE Baseurl $MISP_BASEURL"

# Generate a GPG encryption key.
cat >/tmp/gen-key-script <<EOF
    %echo Generating a default key
    Key-Type: default
    Key-Length: $GPG_KEY_LENGTH
    Subkey-Type: default
    Name-Real: $GPG_REAL_NAME
    Name-Comment: $GPG_COMMENT
    Name-Email: $GPG_EMAIL_ADDRESS
    Expire-Date: 0
    Passphrase: $GPG_PASSPHRASE
    # Do a commit here, so that we can later print "done"
    %commit
    %echo done
EOF

gpg --homedir /var/www/MISP/.gnupg --batch --gen-key /tmp/gen-key-script
rm -f /tmp/gen-key-script
chown -R apache:apache /var/www/MISP/.gnupg

# And export the public key to the webroot
gpg --homedir /var/www/MISP/.gnupg --export --armor $GPG_EMAIL_ADDRESS | tee /var/www/MISP/app/webroot/gpg.asc
chown apache:apache /var/www/MISP/app/webroot/gpg.asc

# Start the workers to enable background jobs
chmod +x /var/www/MISP/app/Console/worker/start.sh
sudo -u apache /usr/bin/scl enable rh-php71 /var/www/MISP/app/Console/worker/start.sh

# To make the background workers start on boot
echo "su -s /bin/bash apache -c 'scl enable rh-php71 /var/www/MISP/app/Console/worker/start.sh'" >> /etc/rc.local
# and make sure it will execute
chmod +x /etc/rc.local

# Initialize user and fetch Auth Key
sudo -E /usr/bin/scl enable rh-php71 "$CAKE userInit -q"
AUTH_KEY=$(mysql -u $DBUSER_MISP -p$DBPASSWORD_MISP misp -e "SELECT authkey FROM users;" | tail -1)
# Setup some more MISP default via cake CLI

# Tune global time outs
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Session.autoRegenerate" 0"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Session.timeout" 600"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Session.cookie_timeout" 3600"

# Enable GnuPG
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "GnuPG.email" "admin@admin.test""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "GnuPG.homedir" "$PATH_TO_MISP/.gnupg""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "GnuPG.password" "Password1234""


# Enable Enrichment set better timeouts
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Enrichment_services_enable" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Enrichment_hover_enable" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Enrichment_timeout" 300"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Enrichment_hover_timeout" 150"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Enrichment_cve_enabled" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Enrichment_dns_enabled" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Enrichment_services_url" "http://127.0.0.1""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Enrichment_services_port" 6666"

# Enable Import modules set better timout
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Import_services_enable" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Import_services_url" "http://127.0.0.1""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Import_services_port" 6666"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Import_timeout" 300"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Import_ocr_enabled" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Import_csvimport_enabled" true"

# Enable Export modules set better timout
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Export_services_enable" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Export_services_url" "http://127.0.0.1""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Export_services_port" 6666"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Export_timeout" 300"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Export_pdfexport_enabled" true"

# Enable installer org and tune some configurables
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.host_org_id" 1"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.email" "info@admin.test""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.disable_emailing" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.contact" "info@admin.test""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.disablerestalert" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.showCorrelationsOnIndex" true"

# Provisional Cortex tunes
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_services_enable" false"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_services_url" "http://127.0.0.1""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_services_port" 9000"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_timeout" 120"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_services_url" "http://127.0.0.1""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_services_port" 9000"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_services_timeout" 120"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_services_authkey" """
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_ssl_verify_peer" false"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_ssl_verify_host" false"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Cortex_ssl_allow_self_signed" true"

# Various plugin sightings settings
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Sightings_policy" 0"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Sightings_anonymise" false"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.Sightings_range" 365"

# Plugin CustomAuth tuneable
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.CustomAuth_disable_logout" false"

# RPZ Plugin settings

sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_policy" "DROP""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_walled_garden" "127.0.0.1""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_serial" "\$date00""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_refresh" "2h""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_retry" "30m""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_expiry" "30d""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_minimum_ttl" "1h""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_ttl" "1w""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_ns" "localhost.""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_ns_alt" """
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Plugin.RPZ_email" "root.localhost""

# Force defaults to make MISP Server Settings less RED
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.language" "eng""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.proposals_block_attributes" false"

## Redis block
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.redis_host" "127.0.0.1""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.redis_port" 6379"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.redis_database" 13"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.redis_password" """

# Force defaults to make MISP Server Settings less YELLOW
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.ssdeep_correlation_threshold" 40"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.extended_alert_subject" false"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.default_event_threat_level" 4"

sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.enableEventBlacklisting" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.enableOrgBlacklisting" true"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.log_client_ip" false"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.log_auth" false"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.disableUserSelfManagement" false"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.block_event_alert" false"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.block_event_alert_tag" "no-alerts=\"true\"""
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "MISP.block_old_event_alert" false"

# Force defaults to make MISP Server Settings less GREEN
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Security.password_policy_length" 12"

# Tune global time outs
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Session.autoRegenerate" 0"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Session.timeout" 600"
sudo /usr/bin/scl enable rh-php71 "$CAKE Admin setSetting "Session.cookie_timeout" 3600"

# restart at the end to ensure config is picked up and correct
systemctl restart rh-php71-php-fpm.service
