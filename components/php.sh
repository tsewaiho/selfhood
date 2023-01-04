# Php
#
# With correct tuning, mod_php and php-fpm should deliver similar performance, where mod_php by default already faster
# but consume more memory, php-fpm could be as fast, better permission control and use less memory, with correct setting.
# https://www.gaelanlloyd.com/blog/apache-performance-benchmarks/
# https://forum.codeigniter.com/thread-76403.html

apt-get install -y apache2 php7.4-fpm 


# Enable php-fpm on Apache2
a2enmod proxy_fcgi setenvif
a2enconf php7.4-fpm
systemctl restart apache2

# php-fpm tuning
# pm.max_children is similar to Apache MaxRequestWorkers on prefork, which default value is 256.
# https://httpd.apache.org/docs/2.4/mod/mpm_common.html#maxrequestworkers
# sed -i '/pm =/c pm = static' /etc/php/7.4/fpm/pool.d/www.conf
# sed -i '/pm.max_children =/c pm.max_children = 256' /etc/php/7.4/fpm/pool.d/www.conf
# systemctl restart php7.4-fpm.service
