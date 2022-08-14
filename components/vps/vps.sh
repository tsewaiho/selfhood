# VPS - A VPS for all external services, like TCP load-balancer, email gateway (rDNS)
#
# Environment variables
#  - DOMAIN
#  - VPS_TUNNEL_SUBNET=10.0.0.0/30
#  - TIMEZONE
#
# Output variables
#  - vps_ip_address
#
# Required function
#  - server_setup

declare vps_ip_address

# Software
vps_install () {
	apt-get install -y wireguard-tools ipcalc-ng

	local vps_wg_ip_address home_server_wg_ip_address
	vps_wg_ip_address=$(ipcalc-ng --minaddr --no-decorate $VPS_TUNNEL_SUBNET)
	home_server_wg_ip_address=$(ipcalc-ng --maxaddr --no-decorate $VPS_TUNNEL_SUBNET)

	# Generate WireGuard key pairs
	local vps_privatekey vps_publickey home_server_privatekey home_server_publickey
	local -a guest_privatekeys guest_publickeys
	vps_privatekey=$(wg genkey)
	vps_publickey=$(wg pubkey <<<$vps_privatekey)
	home_server_privatekey=$(wg genkey)
	home_server_publickey=$(wg pubkey <<<$home_server_privatekey)
	for i in {1..4}
	do
		guest_privatekeys[$i]=$(wg genkey)
		guest_publickeys[$i]=$(wg pubkey <<<${guest_privatekeys[$i]})
	done

	# Create the gateway instance
	# The gateway will have a dnscrypt-proxy service for VPN client, but the server intentionally
	#   not using it because do not want to mess with DHClient.
	local vps_user_data_template vps_user_data
	vps_user_data_template=$(cat $(dirname ${BASH_SOURCE[0]})/vps_user_data_base.sh $BASE/components/dnscrypt-proxy.sh | sed '/^\s*#/d')
	vps_user_data=$(cat <<-ENDUSERDATA
	#!/bin/bash

	vps_wg_ip_address=$vps_wg_ip_address
	home_server_wg_ip_address=$home_server_wg_ip_address
	vps_privatekey=$vps_privatekey
	home_server_publickey=$home_server_publickey
	guest_publickeys=(${guest_publickeys[@]})
	TIMEZONE=$TIMEZONE

	$vps_user_data_template
	dnscrypt_proxy_install
	dnscrypt_proxy_cron
	ENDUSERDATA
	)

	vps_server_setup_and_pair

	# Wait for the gateway instance
	# Find below sentence in the /var/log/syslog on the VM to check to time, or verify whether the script has finished.
	#   Jun  9 18:48:43 server-1 systemd[1]: Startup finished in 3.685s (kernel) + 29.649s (userspace) = 33.334s.
	echo 'Waiting for the gateway instance initialization (normally finished in 1 minutes)...'
	until ping -q -w 90 -c 1 $vps_wg_ip_address; do
		echo 'The vps cannot be reached, do you want to re-install the vps instance?'
		select choice in 'reinstall' 'retry' 'exit'; do
			case $choice in
				reinstall )
					echo "Re-install the instance..."
					vps_server_setup_and_pair
					break
					;;
				retry )
					echo "Retry ping..."
					break
					;;
				exit )
					echo "The installation is stopped."
					exit 1
					;;
			esac
		done
	done

	ssh-keyscan -t ed25519 $vps_wg_ip_address >>$HOME/.ssh/known_hosts

	tee /etc/systemd/system/internet-webserver.service <<-EOF >/dev/null
	[Unit]
	Description=Open the webserver to Internet
	After=network-online.target
	Wants=network-online.target

	[Service]
	Type=oneshot
	RemainAfterExit=yes
	ExecStart=iptables -A INPUT -p tcp --dport 80 -j ACCEPT
	ExecStart=iptables -A INPUT -p tcp --dport 443 -j ACCEPT
	ExecStop=iptables -D INPUT -p tcp --dport 80 -j ACCEPT
	ExecStop=iptables -D INPUT -p tcp --dport 443 -j ACCEPT

	[Install]
	WantedBy=multi-user.target
	EOF
	systemctl daemon-reload
}

vps_server_setup_and_pair () {
	server_setup 'server-1' "$DOMAIN" "$vps_user_data" vps_ip_address

	tee /etc/wireguard/vps.conf <<-EOF >/dev/null
	[Interface]
	Address = $home_server_wg_ip_address/30
	PrivateKey = $home_server_privatekey
	Table = $VPS_INTERFACE_TABLE
	PreUp = ip rule add from $home_server_wg_ip_address/32 lookup $VPS_INTERFACE_TABLE priority $VPS_INTERFACE_TABLE_PRIORITY
	PostDown = ip rule del from $home_server_wg_ip_address/32 lookup $VPS_INTERFACE_TABLE priority $VPS_INTERFACE_TABLE_PRIORITY

	[Peer]
	PublicKey = $vps_publickey
	Endpoint = $vps_ip_address:51820
	AllowedIPs = 0.0.0.0/0
	PersistentKeepalive = 25
	EOF
	systemctl enable wg-quick@vps
	systemctl restart wg-quick@vps
}
