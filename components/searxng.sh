# searxng

searxng_install () {
	until docker pull searxng/searxng; do
		echo 'Docker pull searxng/searxng failed. Retry in 5 seconds...'
		sleep 5
	done
 
	tee /etc/systemd/system/searxng.service <<-EOF >/dev/null
	[Unit]
	Description=SearXNG - Privacy-respecting, hackable metasearch engine
	After=docker.service

	[Service]
	Type=simple
	ExecStart=/usr/bin/docker run --rm \\
	  -p 127.0.0.1:8080:8080  \\
	  -v /etc/searxng:/etc/searxng \\
	  --dns $docker_subnet_with_vpn_gateway \\
	  --network docker_vpn \\
	  --name searxng \\
	  searxng/searxng
	ExecStop=/usr/bin/docker container rm -f searxng
	Restart=always

	[Install]
	WantedBy=multi-user.target
	EOF

	mkdir -p /etc/searxng
	tee /etc/searxng/settings.yml <<-EOF >/dev/null
	use_default_settings: true
	general:
	  enable_metrics: false

	search:
	  autocomplete: "google"
	  autocomplete_min: 4
	  default_lang: "en-US"

	outgoing:
	  request_timeout: 6
	  max_request_timeout: 15.0

	server:
	  base_url: https://searxng.$DOMAIN/
	  secret_key: $(head -c 32 /dev/urandom | base64 -w 0)
	EOF
	chmod -R u=rwX,g=rX,o=rX /etc/searxng
	systemctl restart searxng
	systemctl enable searxng

	

	tee /etc/apache2/sites-available/searxng.conf <<-EOF >/dev/null
	<VirtualHost *:80>
	  ServerName searxng.$DOMAIN
	  Redirect "/" "https://searxng.$DOMAIN/"
	</VirtualHost>

	<VirtualHost *:443>
	  ServerName searxng.$DOMAIN
	  SSLEngine on
	  Header always set Strict-Transport-Security "max-age=63072000"

	  ProxyPass           / http://127.0.0.1:8080/
	  ProxyPassReverse    / http://127.0.0.1:8080/
	</VirtualHost>
	EOF
	a2ensite searxng.conf
	systemctl restart apache2
}
