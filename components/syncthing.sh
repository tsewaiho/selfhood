# Syncthing

syncthing_install () {
	wget https://syncthing.net/release-key.gpg -O /usr/share/keyrings/syncthing-archive-keyring.gpg
	echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" >/etc/apt/sources.list.d/syncthing.list
	apt-get update
	apt-get install -y syncthing

	useradd -d /var/lib/syncthing -s /usr/sbin/nologin syncthing
	mkdir /var/lib/syncthing
	chown syncthing:syncthing /var/lib/syncthing
	chmod 700 /var/lib/syncthing

	sudo -u syncthing syncthing generate --gui-user=admin --gui-password=admin --no-default-folder --skip-port-probing
	systemctl enable --now syncthing@syncthing

	until sudo -u syncthing syncthing cli show system >/dev/null; do
		sleep 1
	done

	# Syncthing local discovery seems do not work on WireGuard, because it do not broadcast on the VPN subnet.
	#   tcpdump show that it only broadcast on 192.168.1.255, but relying on global discovery is very slow.
	#   Current the best method is type quic://syncthing.tsewaiho.me on the android device, and
	#   type tcp://syncthing.tsewaiho.me on Windows because it will always drop connection when using quic.
	sudo -u syncthing syncthing cli config folders add --id=dcim --label=DCIM --path='~/DCIM'
	sudo -u syncthing syncthing cli config options uraccepted set -- -1
	sudo -u syncthing syncthing cli config options natenabled set false
	sudo -u syncthing syncthing cli config options global-ann-enabled set false
	sudo -u syncthing syncthing cli config options local-ann-enabled set false
	sudo -u syncthing syncthing cli config options relays-enabled set false
	sudo -u syncthing syncthing cli config options reconnect-intervals set 5
	# sudo -u syncthing syncthing cli config options raw-listen-addresses 0 set ''
	# sudo -u syncthing syncthing cli config options raw-listen-addresses 0 set quic://$VIRTUAL_IP_ADDRESS:22000

	# If peer devices have non-matched ignore pattern, the folder will stuck at 99% sync.
	# On each device, add its own folder first, before pairing device. 
	# On Windows, need to configure desktop.ini on ignore pattern.
	# The default ignore patthern needs to set before creating folders, because it is just a template.


	tee /etc/apache2/sites-available/syncthing.conf <<-EOF >/dev/null
	<VirtualHost *:80>
		ServerName syncthing.$DOMAIN
		Redirect "/" "https://syncthing.$DOMAIN/"
	</VirtualHost>

	<VirtualHost *:443>
		ServerName syncthing.$DOMAIN
		SSLEngine on
		Header always set Strict-Transport-Security "max-age=63072000"
		RequestHeader set "X-Forwarded-Proto" expr=%{REQUEST_SCHEME}

		ProxyPass / http://localhost:8384/
		ProxyPassReverse / http://localhost:8384/

		<Location "/">
			Require ip $USER_DEVICE_SUBNET
		</Location>
	</VirtualHost>
	EOF

	a2ensite syncthing.conf
	systemctl reload apache2
}
