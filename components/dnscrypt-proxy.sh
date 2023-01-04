# DNS
# Quad9 is the best DNS for privacy, based on Switzerland.
# server_names 'quad9-dnscrypt-ip4-filter-pri' is the only one using the recommended 9.9.9.9 and DNSCrypt.
# Cache is enabled by default, even if this option is not specified in dnscrypt-proxy.toml.

dnscrypt_proxy_install () {
	apt-get install -y dnscrypt-proxy bind9-dnsutils
	systemctl disable --now dnscrypt-proxy.socket
	systemctl disable --now dnscrypt-proxy.service
	systemctl disable --now dnscrypt-proxy-resolvconf.service

	sed -i "/listen_addresses = /c listen_addresses = ['0.0.0.0:53']" /etc/dnscrypt-proxy/dnscrypt-proxy.toml
	sed -i "/server_names = /c server_names = ['quad9-dnscrypt-ip4-filter-pri']" /etc/dnscrypt-proxy/dnscrypt-proxy.toml
	sed -i "/server_names = /a ##INSERT##" /etc/dnscrypt-proxy/dnscrypt-proxy.toml
	sed -i "/##INSERT##/i block_ipv6 = true" /etc/dnscrypt-proxy/dnscrypt-proxy.toml
	sed -i "/##INSERT##/i cloaking_rules = 'cloaking-rules.txt'" /etc/dnscrypt-proxy/dnscrypt-proxy.toml
	echo -e "[blocked_names]\n  blocked_names_file = 'oisd_dblw_full.txt'" >>/etc/dnscrypt-proxy/dnscrypt-proxy.toml

	touch /etc/dnscrypt-proxy/cloaking-rules.txt
	touch /etc/dnscrypt-proxy/oisd_dblw_full.txt
	# This website may down but have no mirror. But this is not a essential component.
	wget https://dblw.oisd.nl/ -O /etc/dnscrypt-proxy/oisd_dblw_full.txt || true

	(cd /etc/dnscrypt-proxy && dnscrypt-proxy -service install)

	systemctl enable --now dnscrypt-proxy.service
	dnscrypt_proxy_wait
}

# Wait for dnscrypt-proxy startup
# The dig command will have 5 second timeout and 2 retry by default, which is enough for dnscrypt-proxy to startup.
dnscrypt_proxy_wait () {
	until dig @127.0.0.1 dns.quad9.net; do
		echo 'The local DNS server do not work, choose what to do.'
		select choice in 'retry' 'exit'; do
			case $choice in
				retry )
					echo "retry"
					break
					;;
				exit )
					echo "The installation is stopped."
					exit 1
					;;
			esac
		done
	done
}

dnscrypt_proxy_cron () {
	# CRON job - Update the DNS filter
	tee /etc/cron.d/dnscrypt <<-EOF >/dev/null
	PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	0 5 * * * root wget https://dblw.oisd.nl/ -O /etc/dnscrypt-proxy/oisd_dblw_full.txt ; systemctl restart dnscrypt-proxy.service
	EOF
}


# Make the DHCP Client use the local dnscrypt-proxy
#echo 'supersede domain-name-servers 127.0.0.1;' >>/etc/dhcp/dhclient.conf

# Restart dhcp so that 127.0.0.1 can propagate to /etc/resolv.conf
# `dhclient -r eth0;dhclient eth0`
# Or
# `ip addr flush dev eth0 ; dhclient eth0`
