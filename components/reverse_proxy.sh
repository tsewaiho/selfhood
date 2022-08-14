# VPN reverse proxy
#
# Environment variables
#  - DOMAIN
#  - EMAIL
#  - USER_DEVICE_SUBNET

reverse_proxy_install () {
	# Software
	apt-get install -y apache2


	# Get a wildcard cert for the domain
	certbot_get_cert "$DOMAIN" "*.$DOMAIN" "$EMAIL"

	# Apache
	# Common attributes for TLS
	# Browser will ignore Strict-Transport-Security when using test cert.
	# Strict-Transport-Security make browser redirect any http request to https.
	#
	# Do not use the multiple commands syntax on sed because c and i do not support.
	# https://www.gnu.org/software/sed/manual/html_node/Multiple-commands-syntax.html
	minify /etc/apache2/mods-available/ssl.conf
	sed -i '/SSLCipherSuite/c SSLCipherSuite TLSv1.3 TLS_CHACHA20_POLY1305_SHA256' /etc/apache2/mods-available/ssl.conf
	sed -i '/SSLProtocol/c SSLProtocol TLSv1.3' /etc/apache2/mods-available/ssl.conf
	sed -i '/<\/IfModule>/i SSLOpenSSLConfCmd Curves secp384r1' /etc/apache2/mods-available/ssl.conf
	sed -i '/<\/IfModule>/i SSLSessionTickets off' /etc/apache2/mods-available/ssl.conf
	sed -i '/<\/IfModule>/i SSLUseStapling on' /etc/apache2/mods-available/ssl.conf
	sed -i '/<\/IfModule>/i SSLStaplingCache "shmcb:ssl_stapling(32768)"' /etc/apache2/mods-available/ssl.conf
	sed -i "/<\/IfModule>/i SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem" /etc/apache2/mods-available/ssl.conf
	sed -i "/<\/IfModule>/i SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/apache2/mods-available/ssl.conf

	# HTTP/2
	# HTTP/2 is slower than HTTP1.1 on upload and have similar speed on download because of flow control issue.
	# https://forum.seafile.com/t/http2-drastically-slows-down-up-and-download/15472
	# https://github.com/dotnet/runtime/issues/43086
	#
	# But the webpage loading time of HTTP/2 for ownCloud is much better in around 4s where HTTP1.1 is around 16s.
	#
	# The flow control can be tuned by H2WindowSize, the value could be 65535 multiply 2^x where x < 14.
	# https://en.wikipedia.org/wiki/TCP_window_scale_option#TCP_windows
	#
	# The best I can do is upload 9MiB file without vpn in 9 seconds, and over vpn in 13 seconds, by setting H2WindowSize 4194240.
	#   But http1.1 can do it in 2 seconds without vpn, and 4 seconds over vpn at the best situation.
	#
	# Do not need to specify 'Protocols h2' manauly because the http2.conf already did it.
	sed -i "/<\/IfModule>/i H2WindowSize 4194240" /etc/apache2/mods-available/http2.conf

	# Enable proxy protocol for public address, exclude the VPN trusted client subnet
	#   and the Docker bridged network 172.17.0.0/16, but include the gateway IP 
	#   address (10.0.0.1) otherwise proxy protocol do not work.
	#
	# a2enmod remoteip
	# tee /etc/apache2/mods-available/remoteip.conf <<-EOF >/dev/null
	# RemoteIPProxyProtocol On
	# RemoteIPProxyProtocolExceptions $USER_DEVICE_SUBNET 172.17.0.0/16
	# EOF

	# Disable the default site will not prevent Apache showing this site when no virtualhost is matched.
	# This is the fallback mechanism when no virtualhost is matched.
	# 
	# a2dissite 000-default.conf

	# Debugging. Allow test case to test web server connectivity.
	echo 'ok' >/var/www/html/ok.html

	a2disconf other-vhosts-access-log

	# These modules are for setup that HAProxy TCP load balancer as frontend and Apache HTTPS server as backend.
	a2enmod ssl headers http2 proxy proxy_http proxy_wstunnel

	systemctl restart apache2
}
