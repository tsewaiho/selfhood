# vaultwarden

vaultwarden_install () {
	until docker run -d \
		-e "IP_HEADER=X-Forwarded-For" \
		-e "DOMAIN=https://vaultwarden.$DOMAIN" \
		-e "ADMIN_TOKEN=admin" \
		-e "WEBSOCKET_ENABLED=true" \
		-p 127.0.0.1:8008:80 \
		-p 127.0.0.1:3012:3012 \
		-v /var/lib/vaultwarden:/data \
		--restart always \
		--name vaultwarden \
		vaultwarden/server
	do
		echo 'Docker run vaultwarden failed. Retry in 5 seconds...'
		sleep 5
	done

	tee /etc/apache2/sites-available/vaultwarden.conf <<-EOF >/dev/null
	<VirtualHost *:80>
		ServerName vaultwarden.$DOMAIN
		Redirect "/" "https://vaultwarden.$DOMAIN/"
	</VirtualHost>

	<VirtualHost *:443>
		ServerName vaultwarden.$DOMAIN
		SSLEngine on
		Header always set Strict-Transport-Security "max-age=63072000"

		ProxyPass           /notifications/hub ws://127.0.0.1:3012/

		ProxyPass           / http://127.0.0.1:8008/
		ProxyPassReverse    / http://127.0.0.1:8008/
	</VirtualHost>
	EOF
	a2ensite vaultwarden.conf
	systemctl reload apache2
}
