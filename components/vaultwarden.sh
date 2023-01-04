# vaultwarden
# All configuration is in https://github.com/dani-garcia/vaultwarden/blob/main/.env.template

vaultwarden_install () {
	# until docker run -d \
	# 	-e "IP_HEADER=X-Forwarded-For" \
	# 	-e "DOMAIN=https://vaultwarden.$DOMAIN" \
	# 	-e "ADMIN_TOKEN=admin" \
	# 	-e "WEBSOCKET_ENABLED=true" \
	# 	-p 127.0.0.1:8008:80 \
	# 	-p 127.0.0.1:3012:3012 \
	# 	-v /var/lib/vaultwarden:/data \
	# 	--restart always \
	# 	--name vaultwarden \
	# 	vaultwarden/server
	# do
	# 	echo 'Docker run vaultwarden failed. Retry in 5 seconds...'
	# 	sleep 5
	# done

	until docker pull vaultwarden/server; do
		echo 'Docker pull vaultwarden/server failed. Retry in 5 seconds...'
		sleep 5
	done

	tee /etc/systemd/system/vaultwarden.service <<-EOF >/dev/null
	[Unit]
	Description=Vaultwarden is an unofficial Bitwarden server implementation written in Rust
	After=docker.service

	[Service]
	Type=simple
	ExecStart=/usr/bin/docker run --rm \\
	  -p 127.0.0.1:8008:80 \\
	  -p 127.0.0.1:3012:3012 \\
	  -v /var/lib/vaultwarden:/data \\
	  --dns 172.17.0.1 \\
	  --name vaultwarden \\
	  vaultwarden/server
	Restart=always

	[Install]
	WantedBy=multi-user.target
	EOF

	mkdir /var/lib/vaultwarden
	tee /var/lib/vaultwarden/config.json <<-EOF >/dev/null
	{
		"domain": "https://vaultwarden.$DOMAIN",
		"admin_token": "admin",
		"ip_header": "X-Forwarded-For",
		"websocket_enabled": true,
		"smtp_host": "public.$DOMAIN",
		"smtp_security": "starttls",
		"smtp_port": 587,
		"smtp_from": "vaultwarden@$DOMAIN",
		"smtp_from_name": "Vaultwarden",
		"smtp_username": "vaultwarden@$DOMAIN",
		"smtp_password": "vaultwarden"
	}
	EOF
	chmod -R u=rwX,g=rX,o= /var/lib/vaultwarden
	systemctl restart vaultwarden
	systemctl enable vaultwarden

	

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
