# Database
#
# The current version of redis-server backport 5:6.0.16-4~bpo11+1 have error message in the log
#   `Error loading cjson library`. So fallback to non-backport version.

apt-get install -y postgresql-13 redis-server


# Postgres
# template0 is unmodifiable, you can create a “pristine” user database with it.
# Also, template0 allow specifying encoding where template1 do not.
# https://www.postgresql.org/docs/current/manage-ag-templatedbs.html
# Have to use login-shell when using psql, `sudo -i -u postgres psql`, which will change 
#   the working directory the $HOME. Otherwise a warning will prompt.
#
# If the /etc/postgresql/13/main exist before installing postgresql, need to enable it manually.
# systemctl enable postgresql@13-main


# Redis
# Using socket will have better performance
# https://doc.owncloud.com/server/10.9/admin_manual/configuration/server/caching_configuration.html#redis-configuration-using-unix-sockets
sed -i '/^bind 127\.0\.0\.1 ::1/c bind 127.0.0.1' /etc/redis/redis.conf
sed -i '/unixsocket /s/^#\s*//' /etc/redis/redis.conf
usermod -aG redis www-data
systemctl restart redis-server.service
systemctl restart php7.4-fpm.service
