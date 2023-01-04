# ownCloud Server
#
# Environment variables
#  - mode
#  - DOMAIN

# Install bin
cp $(dirname ${BASH_SOURCE[0]})/bin/* /usr/local/bin/
chmod 755 /usr/local/bin/owncloud-*

# User and permission
# Allow ownCloud to use Postgresql and Redis unix domain socket
# Allow Apache2 to read the ownCloud server files.
useradd -m -s /usr/bin/bash -G postgres,redis owncloud
usermod -aG owncloud www-data


# Apache and php dependencies
apt-get install -y \
	php-pgsql php-zip php-xml php-intl php-mbstring php-gd php-curl \
	php-redis php-apcu php-imagick imagemagick-6.q16
a2enmod rewrite headers env dir mime unique_id
systemctl restart apache2


# Apache
# https://doc.owncloud.com/server/10.9/admin_manual/installation/manual_installation/manual_installation_apache.html
tee /etc/apache2/sites-available/owncloud.conf <<EOF >/dev/null
<VirtualHost *:80>
  ServerName owncloud.$DOMAIN
  Redirect "/" "https://owncloud.$DOMAIN/"
</VirtualHost>

<VirtualHost *:443>
  ServerName owncloud.$DOMAIN
  DocumentRoot /var/www/owncloud

  SSLEngine on
  Header always set Strict-Transport-Security "max-age=63072000"

  <FilesMatch ".+\.ph(ar|p|tml)$">
    SetHandler "proxy:unix:/run/php/owncloud.sock|fcgi://localhost"
  </FilesMatch>

  <Directory /var/www/owncloud>
    AllowOverride All
    Satisfy Any
    <IfModule mod_dav.c>
      Dav off
    </IfModule>
  </Directory>
</VirtualHost>
EOF

# Php
tee /etc/php/7.4/fpm/pool.d/owncloud.conf <<EOF >/dev/null
[owncloud]
user = owncloud
group = owncloud

listen = /run/php/owncloud.sock

listen.owner = www-data
listen.group = www-data

pm = static
pm.max_children = 8
pm.max_requests = 500
EOF
systemctl restart php7.4-fpm

## Create a Mariadb dbadmin user for ownCloud database bootstrap
# mysql -e " \
#   CREATE USER dbadmin@localhost IDENTIFIED BY 'password'; \
#   GRANT ALL PRIVILEGES ON *.* TO dbadmin@localhost WITH GRANT OPTION; \
# ";

# Required to specify the port if there is other postgresql instance even if tcp disabled
pg_createcluster --user owncloud --socketdir /var/run/postgresql/owncloud --start -p 5432 13 owncloud

sudo -i -u owncloud psql -h /var/run/postgresql/owncloud postgres <<EOF
DROP DATABASE IF EXISTS owncloud;
CREATE DATABASE owncloud OWNER owncloud TEMPLATE template0 ENCODING 'UTF8';
ALTER USER owncloud PASSWORD 'owncloud';
EOF

# There are two version of ownCloud server package, the Standard and the Minimal. Belows are their naming.
# Standard
#   owncloud-complete-latest.tar.bz2
#   owncloud-complete-20220112.tar.bz2
# Minimal
#   owncloud-latest.tar.bz2
#   owncloud-10.9.1.tar.bz2
wget https://download.owncloud.com/server/stable/owncloud-latest.tar.bz2 -O /var/tmp/owncloud-latest.tar.bz2
wget https://download.owncloud.com/server/stable/owncloud-latest.tar.bz2.sha256 -O /var/tmp/owncloud-latest.tar.bz2.sha256
(cd /var/tmp ; sha256sum -c owncloud-latest.tar.bz2.sha256)
tar xf /var/tmp/owncloud-latest.tar.bz2 -C /var/www

# For upgrade test:
# wget https://download.owncloud.com/server/stable/owncloud-10.10.0.tar.bz2 -O /var/tmp/owncloud-10.10.0.tar.bz2
# wget https://download.owncloud.com/server/stable/owncloud-10.10.0.tar.bz2.sha256 -O /var/tmp/owncloud-latest.tar.bz2.sha256
# (cd /var/tmp ; sha256sum -c owncloud-latest.tar.bz2.sha256)
# tar xf /var/tmp/owncloud-10.10.0.tar.bz2 -C /var/www


# ownCloud bundled Mozilla's root certificates for php_curl to use. But it has china and hong kong certificate included.
# Debian has a single-file version of CA certificates of your choices.
# https://manpages.debian.org/bullseye/ca-certificates/update-ca-certificates.8.en.html
cp /etc/ssl/certs/ca-certificates.crt /var/www/owncloud/resources/config/ca-bundle.crt

# Harden the ownCloud permission
# Prevent www-data to change the content of the core app, except config, data and apps-external
# https://doc.owncloud.com/server/10.9/admin_manual/maintenance/upgrading/manual_upgrade.html#permissions
#
# The use of symbolic link is to make upgrade more convenient
chown -R root:owncloud /var/www/owncloud
chmod -R u=rwX,g=rX,o= /var/www/owncloud
rm -rf /var/www/owncloud/config
ln -s /var/lib/owncloud/data /var/www/owncloud/data
ln -s /var/lib/owncloud/config /var/www/owncloud/config
ln -s /var/lib/owncloud/apps-external /var/www/owncloud/apps-external
mkdir -p /var/lib/owncloud
mkdir /var/lib/owncloud/data
mkdir /var/lib/owncloud/config
mkdir /var/lib/owncloud/apps-external
chown -R owncloud:owncloud /var/lib/owncloud
chmod -R 750 /var/lib/owncloud

# This information do not matter for now because I am using symbolic link for data.
#   After installation, a data directory will appear at owncloud root directory, no matter whether you specify data-dir option.
#   According to core/lib/private/Setup.php, this data directory is to test whether the .htaccess works.
#   This is not necessarily the same data directory as the one that will effectively be used.
#   Remove that part of code will prevent that data directory appear at owncloud root directory.
#
# Unix socket database host:
# It checks whether the text after colon(:) is pure digit or not to distinguish port and unix socket.
# But maintenance:install do not support use socket on PostgreSQL.
# See lib/private/Setup/MySQL.php, lib/private/Setup/PostgreSQL.php, lib/private/DB/ConnectionFactory.php
#
# https://doc.owncloud.com/server/10.9/admin_manual/configuration/server/config_sample_php_parameters.html#define-the-database-server-host-name
#
# runuser -u www-data -- php /var/www/owncloud/occ maintenance:install \
#   --database "mysql" \
#   --database-host "localhost:/run/mysqld/mysqld.sock" \
#   --database-name "owncloud" \
#   --database-user "dbadmin" \
#   --database-pass "password" \
#   --admin-user $OWNCLOUD_ADMIN_USER \
#   --admin-pass $OWNCLOUD_ADMIN_PASS
sudo -u owncloud php /var/www/owncloud/occ maintenance:install \
	--database 'pgsql' \
	--database-name 'owncloud' \
	--database-user 'owncloud' \
	--database-pass 'owncloud' \
	--admin-user 'admin' \
	--admin-pass 'admin'

sudo -u owncloud php /var/www/owncloud/occ config:import <<EOF
{
	"system": {
		"trusted_domains": ["owncloud.$DOMAIN"],
		"dbuser": "owncloud",
		"dbhost": "/var/run/postgresql/owncloud",
		"dbpassword": "",
		"memcache.local": "\\\\OC\\\\Memcache\\\\APCu",
		"memcache.locking": "\\\\OC\\\\Memcache\\\\Redis",
		"overwrite.cli.url": "https://owncloud.$DOMAIN/",
		"htaccess.RewriteBase": "/",
		"redis": {
			"host": "/var/run/redis/redis-server.sock",
			"port": 0,
			"dbindex": 1
		},
		"logtimezone": "Asia/Hong_Kong",
		"integrity.excluded.files": ["resources/config/ca-bundle.crt"],
		"mail_domain": "$DOMAIN",
		"mail_from_address": "owncloud-noreply",
		"mail_smtpmode": "sendmail"
	}
}
EOF

# PostgreSQL only support single quote for config values.
sed -i "/listen_addresses =/c listen_addresses = ''" /etc/postgresql/13/owncloud/postgresql.conf
systemctl restart postgresql@13-owncloud.service

sudo -i -u owncloud psql -h /var/run/postgresql/owncloud owncloud <<EOF
ALTER USER owncloud PASSWORD NULL;
REASSIGN OWNED BY oc_admin TO owncloud;
DROP USER IF EXISTS oc_admin;
EOF

# sudo -u owncloud php /var/www/owncloud/occ config:import <<<'{"system":{"dbuser":"owncloud","dbhost":"/var/run/postgresql/owncloud","dbpassword":""}}'
# sudo -u owncloud php /var/www/owncloud/occ config:system:set memcache.local --value '\OC\Memcache\APCu'
# sudo -u owncloud php /var/www/owncloud/occ config:system:set redis --type json --value '{"host":"/var/run/redis/redis-server.sock","port":0,"dbindex":1}'
# sudo -u owncloud php /var/www/owncloud/occ config:system:set memcache.locking --value '\OC\Memcache\Redis'
# sudo -u owncloud php /var/www/owncloud/occ config:system:set trusted_domains 1 --value "owncloud.$DOMAIN"
# sudo -u owncloud php /var/www/owncloud/occ config:system:set overwrite.cli.url --value "https://owncloud.$DOMAIN"
# sudo -u owncloud php /var/www/owncloud/occ config:system:set htaccess.RewriteBase --value '/'
# sudo -u owncloud php /var/www/owncloud/occ config:system:set logtimezone --value 'Asia/Hong_Kong'
# sudo -u owncloud php /var/www/owncloud/occ config:system:set integrity.excluded.files 0 --value 'resources/config/ca-bundle.crt'


# When using collabora online with letsencrypt test cert,
# add these root certificates to /var/www/owncloud/resources/config/ca-bundle.crt
if [ $mode = 'new-installation' ]; then
	cat $BASE/assets/letsencrypt-stg-root-x1.pem $BASE/assets/letsencrypt-stg-root-x2.pem >>/var/www/owncloud/resources/config/ca-bundle.crt
fi

# ownCloud has defined what is first-class app, these are distributed by ownCloud or listed in Supported Apps in ownCloud.
# In the page of "Supported Apps in ownCloud", those without hyperlink are built-in app.
# These first-class apps do not need to be disabled before ownCloud upgrade.
# First-class app does not mean error-free on app:check-code, the built-in app "files" has many errors.
# https://doc.owncloud.com/server/10.11/admin_manual/maintenance/upgrading/manual_upgrade.html#review-third-party-apps
# Apps that distributed by ownCloud but not listed in Supported Apps seems not well maintained and didn't update for 
#   long time, like Contacts and Calendar

# First-class apps:
owncloud_apps=(files_texteditor files_pdfviewer)
# Distributed by ownCloud but not listed in Supported Apps
# owncloud_apps=(contacts twofactor_totp calendar)

# Well developed but non first-class apps:
owncloud_apps+=(richdocuments)

for app in "${owncloud_apps[@]}"; do
    until sudo -u owncloud php /var/www/owncloud/occ market:install $app; do
		echo "Install ownCloud app $app failed. Retry in 5 seconds..."
		sleep 5
	done
done

# Useful non first-class apps, but within ownCloud repository:
#  - brute_force_protection. But it do not count failed totp.
#  - Music. Without music ownCloud cannot play MP3.
# If ownCloud cannot generate preview on mp3 file, it produce error on the log, so it needs to disable mp3 preview by
#   only enabling common photo format. "OC\Preview\Heic" include both .heic and .heif.
# https://github.com/owncloud/core/issues/34900
# https://github.com/owncloud/core/pull/39084
# https://github.com/owncloud/core/blob/1b62d28abe243a40a0278106b9da9babdbd8c6ad/lib/private/PreviewManager.php
# sudo -u www-data php /var/www/owncloud/occ market:install brute_force_protection
# sudo -u www-data php /var/www/owncloud/occ market:install music
# sudo -u www-data php /var/www/owncloud/occ config:system:set enabledPreviewProviders --type json --value '["OC\\Preview\\JPEG","OC\\Preview\\PNG","OC\\Preview\\Heic"]'
# sudo -u www-data php /var/www/owncloud/occ market:install notes
# sudo -u www-data php /var/www/owncloud/occ market:install tasks
#
# Visit the Office page on the navigation bar will cause "Undefined index" error on the log file. So disable menu_option.
sudo -u owncloud php /var/www/owncloud/occ config:app:set richdocuments wopi_url --value "https://collaboraonline.$DOMAIN"
sudo -u owncloud php /var/www/owncloud/occ config:app:set richdocuments menu_option --value false

chown owncloud:owncloud /var/www/owncloud/.htaccess
sudo -u owncloud php /var/www/owncloud/occ maintenance:update:htaccess

# Harden the .htaccess permission after install or upgrade
# .user.ini is already secured
chown root:owncloud /var/www/owncloud/.htaccess /var/lib/owncloud/data/.htaccess
chmod 640 /var/www/owncloud/.htaccess /var/lib/owncloud/data/.htaccess

# Remove the dbadmin mariadb account which used for bootstrap ownCloud only.
# mysql -e " \
#   DROP USER IF EXISTS dbadmin; \
#   DROP USER IF EXISTS dbadmin@localhost; \
# ";

# Enable the ownCloud website
a2ensite owncloud.conf
systemctl reload apache2

# CRON
#
# The upload file chunks are stored at data/{user}/uploads, unfinished upload will remain orphan chunks at data/{user}/uploads,
# Admin needs to call dav:cleanup-chunks to due with it. The system:cron do not have this job in it.
# https://doc.owncloud.com/server/10.9/admin_manual/configuration/server/background_jobs_configuration.html#cleanupchunks
#   To test chunks cleanup, use "sudo -u www-data faketime '2022-04-19 08:15:42' php occ dav:cleanup-chunks".
#   Do not use systemctl set-time or date --set. Some other background job may reset the time in Debian
#   which make the test unsuccess.

# ownCloud have command to delete a background job from the oc_jobs table, to stop it from running.
# But do not have a command to re-add it back. So do not delete job for now.
# https://github.com/owncloud/core/issues/31743
# https://github.com/owncloud/core/pull/31617
#
# Adding -f to php is optional. Simply mean it is useless.
#
# On Debian, cronjob daemon will send the output to the cronjob owner by mail. Specify MAILTO='' to disable it.
owncloud_cron () {
	tee /etc/cron.d/owncloud <<-EOF >/dev/null
	PATH=/usr/local/bin:/usr/bin:/bin
	MAILTO=''

	*/15 * * * * owncloud php /var/www/owncloud/occ dav:cleanup-chunks
	*/15 * * * * owncloud php /var/www/owncloud/occ system:cron
	EOF
}



# Collabora Online on Docker
#
# Add additional entry to /etc/hosts by `--add-host`
#   https://docs.docker.com/engine/reference/commandline/run/#add-entries-to-container-hosts-file---add-host
#
# old: When hosting DNSCrypt and Docker in the machine, I have to use `--dns 172.17.0.1`, otherwise DNSCrypt response 
#   address may not be the same as the request's destination address. which cause "reply from unexpected source" error.
#   https://github.com/DNSCrypt/dnscrypt-proxy/issues/1362
#
# `docker run` looks like don't have any retry, automatic retry can elminiate some network error.
until docker pull collabora/code; do
	echo 'Docker pull collabora/code failed. Retry in 5 seconds...'
	sleep 5
done

tee /etc/systemd/system/code.service <<EOF >/dev/null
[Unit]
Description=Collabora Online Development Edition (CODE)
After=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/docker run --rm \\
	-e "extra_params= \\
		--o:ssl.enable=false \\
		--o:ssl.termination=true \\
		--o:admin_console.enable=false \\
		--o:server_name=collaboraonline.$DOMAIN \\
		--o:storage.wopi.alias_groups.group[0].host[0]=https://owncloud.$DOMAIN \\
		--o:user_interface.mode=classic \\
	" \\
	-e 'dictionaries=en_US en_GB' \\
	-p 127.0.0.1:9980:9980 \\
	--dns 172.17.0.1 \\
	--add-host=owncloud.$DOMAIN:172.17.0.1 \\
	--name code \\
	collabora/code
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl restart code
systemctl enable code

# allowed_languages (dictionaries) must be specified by "-e" because it contains spaces
# https://github.com/CollaboraOnline/online/issues/1235#event-4218393697
#
# Turns out that Collabora inherit Firefox theme, and cannot be overide. Choose light theme on Firefox can fix 
#   the hard-to-use dark theme issue on Collabora.
#
# old: 21.11.4.1.1 is the last version that can control user_interface.mode=classic, the later version is changed
#   to user_interface.mode=compact, but this setting has no effect and it is still not fixed in 21.11.5.1.1.
#
# old: 21.11.4.2.1 is the last version has default light theme, later version use hard-to-use dark theme, cannot be changed
#   and it is still not fixed in 21.11.5.1.1.

# Collabora Online
# You need to either set the server_name or ProxyPreserveHost
# Because answers from coolwsd server must contain the original host name, otherwise the connection will fail.
# https://sdk.collaboraonline.com/docs/installation/Proxy_settings.html#configure-collabora-online
tee /etc/apache2/sites-available/collaboraonline.conf <<EOF >/dev/null
<VirtualHost *:443>
	ServerName collaboraonline.$DOMAIN
	SSLEngine on
	Header always set Strict-Transport-Security "max-age=63072000"
	AllowEncodedSlashes NoDecode
	ProxyPass           /browser http://127.0.0.1:9980/browser retry=0
	ProxyPassReverse    /browser http://127.0.0.1:9980/browser
	ProxyPass           /hosting/discovery http://127.0.0.1:9980/hosting/discovery retry=0
	ProxyPassReverse    /hosting/discovery http://127.0.0.1:9980/hosting/discovery
	ProxyPass           /hosting/capabilities http://127.0.0.1:9980/hosting/capabilities retry=0
	ProxyPassReverse    /hosting/capabilities http://127.0.0.1:9980/hosting/capabilities
	ProxyPassMatch      "/cool/(.*)/ws$" ws://127.0.0.1:9980/cool/\$1/ws nocanon
	ProxyPass           /cool/adminws ws://127.0.0.1:9980/cool/adminws
	ProxyPass           /cool http://127.0.0.1:9980/cool
	ProxyPassReverse    /cool http://127.0.0.1:9980/cool
	ProxyPass           /lool http://127.0.0.1:9980/cool
	ProxyPassReverse    /lool http://127.0.0.1:9980/cool
</VirtualHost>
EOF
a2ensite collaboraonline.conf
systemctl reload apache2
