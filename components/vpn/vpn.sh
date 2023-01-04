# VPN - VPN service for user devices
#
# Environment variables and example
#  - USER_DEVICE_SUBNET=10.1.0.0/24
#  - PLACEHOLDER_SUBNET=10.255.255.0/24
#  - USER_DEVICES=(mobile tablet laptop desktop)
#  - GATEWAY_TABLE_START_FROM=200
#  - HOSTNAME
#  - DOMAIN
#  - MASTER_PASSWORD
#
# Output variable
#  - server_ip_address_for_user_device
#
# Required function
#  - random-sleep
#
# Required node services
#  - DNS server

declare server_ip_address_for_user_device vpn_crons

vpn_install () {
	# Software
	#
	# You can generate WireGuard configuration QR code with qrencode
	apt-get install -y wireguard-tools ipcalc-ng prips iptables zip bind9-dnsutils argon2 qrencode

	cp $(dirname ${BASH_SOURCE[0]})/bin/* /usr/local/bin/
	chmod 755 /usr/local/bin/vpn-*

	local user_device_subnet_prefix user_device_subnet_chunk_prefix
	local -a wg_config_files user_device_subnet_chunks user_device_subnet_per_tunnel placeholder_ips

	# Example: 24
	user_device_subnet_prefix=$(awk -F/ '{print $2}' <<<$USER_DEVICE_SUBNET)

	# Example: 30 for 4 devices, 29 for 8 devices
	user_device_subnet_chunk_prefix=$(for i in {1..24};do [ $((2**$i)) -ge ${#USER_DEVICES[@]} ] && echo $((32-$i)) && break;done)

	
	wg_config_files=($(ls $BASE/credentials/wg_config_files))

	# The number of subnet that can split minus the first and last subnet needs to be large than user supplied tunnel.
	if [ ${#wg_config_files[@]} -gt $(( 2**($user_device_subnet_chunk_prefix-$user_device_subnet_prefix)-2 )) ]; then
		echo 'USER_DEVICE_SUBNET is not large enough to fit the user device and tunnel combinations.'
		exit 1
	fi

	# Example: 10.1.0.0/30 10.1.0.4/30 10.1.0.8/30 ......
	user_device_subnet_chunks=($(ipcalc-ng -S $user_device_subnet_chunk_prefix --no-decorate $USER_DEVICE_SUBNET))

	# Example: 10.1.0.1
	server_ip_address_for_user_device=$(ipcalc-ng --minaddr --no-decorate ${user_device_subnet_chunks[0]})

	# Example: 10.1.0.4/30 10.1.0.8/30 10.1.0.12/30 ......
	user_device_subnet_per_tunnel=(${user_device_subnet_chunks[@]:1:${#user_device_subnet_chunks[@]}-2})

	# Example: 10.255.255.1 10.255.255.1 10.255.255.2 ......
	# the `-d 32` mean separate by space (ANSI code 32)
	# The first and last address is removed
	placeholder_ips=($(prips -d 32 $PLACEHOLDER_SUBNET))
	placeholder_ips=(${placeholder_ips[@]:1:${#placeholder_ips[@]}-2})

	## Generate gateway tunnel configurations

	# FORWARD ACCEPT needs to be per-subnet because there is a dangerous situation, where the router has enabled 
	#   masquerade, and the subnet is assigned to lookup a table, but the gateway tunnel of that table is down, 
	#   so that no entries exist in that table.
	#   Then, the request will fallback to the main table, using the un-encrypted physical interface.
	#
	# The PostUp ping may sometimes fail, so make it optionally by `|| true`
	for i in "${!wg_config_files[@]}"
	do
		local -a conf if_name lookup_table
		conf=($(cat <<-EOF | python3
			import configparser
			config = configparser.ConfigParser()
			config.read('$BASE/credentials/wg_config_files/${wg_config_files[$i]}')
			print(config.get('Interface', 'PrivateKey'))
			print(config.get('Interface', 'Address'))
			print(config.get('Peer', 'PublicKey'))
			print(config.get('Peer', 'Endpoint'))
			EOF
		))
		if_name=$(awk -F. '{print $1}' <<<${wg_config_files[$i]})
		lookup_table=$(($GATEWAY_TABLE_START_FROM+$i))

		tee /etc/wireguard/${wg_config_files[$i]} <<-EOF >/dev/null
		[Interface]
		PrivateKey = ${conf[0]}
		Address = ${placeholder_ips[$i]}/32
		Table = $lookup_table
		Preup = iptables -t nat -A POSTROUTING -o %i -j SNAT --to $(awk -F/ '{print $1}' <<<${conf[1]})
		PostDown = iptables -t nat -D POSTROUTING -o %i -j SNAT --to $(awk -F/ '{print $1}' <<<${conf[1]})
		PreUp = ip rule add from ${user_device_subnet_per_tunnel[$i]} lookup $lookup_table priority $GATEWAY_PRIORITY
		PostDown = ip rule del from ${user_device_subnet_per_tunnel[$i]} lookup $lookup_table priority $GATEWAY_PRIORITY
		PostUp = iptables -A FORWARD -s ${user_device_subnet_per_tunnel[$i]} -j ACCEPT
		PreDown = iptables -D FORWARD -s ${user_device_subnet_per_tunnel[$i]} -j ACCEPT
		PostUp = ping -q -c 1 -I %i $(awk -F: '{print $1}' <<<${conf[3]}) || true

		[Peer]
		PublicKey = ${conf[2]}
		AllowedIPs = 0.0.0.0/0
		Endpoint = ${conf[3]}
		EOF
		systemctl enable --now wg-quick@$(awk -F. '{print $1}' <<<${wg_config_files[$i]})

		vpn_crons+="* * * * * root vpn-fault-detect '$if_name' '$vps_ip_address' '$DOCKER_SUBNET_WITH_VPN' '$lookup_table' '$(($GATEWAY_PRIORITY+1+$i))'"$'\n'
	done

	## Generate WireGuard key pairs for the server and user devices
	local server_privatekey server_publickey
	local -a user_device_privatekeys user_device_publickeys
	# server_privatekey=$(echo -n "$HOSTNAME.$DOMAIN" | argon2 "$MASTER_PASSWORD" -r | xxd -r -p | base64 -w 0)
	server_privatekey=$(base64_hash "$HOSTNAME.$DOMAIN")
	server_publickey=$(wg pubkey <<<$server_privatekey)
	for i in "${!USER_DEVICES[@]}"
	do
		# user_device_privatekeys[$i]=$(echo -n "${USER_DEVICES[$i]}" | argon2 "$MASTER_PASSWORD" -r | xxd -r -p | base64 -w 0)
		user_device_privatekeys[$i]=$(base64_hash "${USER_DEVICES[$i]}")
		user_device_publickeys[$i]=$(wg pubkey <<<${user_device_privatekeys[$i]})
	done

	# Generate WireGuard configuration for end-user devices,
	#   and prepare the peer's allowed_ips for server WireGuard configuration
	local -a peer_allowed_ips

	for device_name in "${USER_DEVICES[@]}"
	do
		mkdir -p /root/wireguard-configs/$device_name
	done

	for tunnel_i in "${!wg_config_files[@]}"
	do
		local addresses_in_tunnel_subnet
		addresses_in_tunnel_subnet=($(prips -d 32 ${user_device_subnet_per_tunnel[$tunnel_i]}))

		for device_i in "${!USER_DEVICES[@]}"
		do
			local PostUp=''
			if [[ ${USER_DEVICES[$device_i]} =~ 'windows' ]]; then
				PostUp='PostUp = powershell.exe -command "Set-NetConnectionProfile -InterfaceAlias %WIREGUARD_TUNNEL_NAME% -NetworkCategory Private"'
			fi

			# Only alphanumeric characters are safe to use on tunnel name for cross platform compatiablilty
			tee /root/wireguard-configs/${USER_DEVICES[$device_i]}/${wg_config_files[$tunnel_i]} <<-EOF >/dev/null
				[Interface]
				Address = ${addresses_in_tunnel_subnet[$device_i]}/$user_device_subnet_prefix
				PrivateKey = ${user_device_privatekeys[$device_i]}
				DNS = $server_ip_address_for_user_device
				$PostUp

				[Peer]
				PublicKey = $server_publickey
				Endpoint = $HOSTNAME.$DOMAIN:$INTERFACE_USER_DEVICE_LISTEN
				AllowedIPs = 0.0.0.0/0
				PersistentKeepalive = 25
			EOF
			peer_allowed_ips[$device_i]+="${addresses_in_tunnel_subnet[$device_i]}/32,"
		done
	done

	# Generate zip file of user device WireGuard configuration for convenient import
	cd /root/wireguard-configs
	for device_name in "${USER_DEVICES[@]}"
	do
		zip -j $device_name.zip $device_name/*
	done

	## Generate server WireGuard configuration
	local Peers
	for i in "${!USER_DEVICES[@]}"
	do
		local peer
		peer=$(cat <<-EOF
		#${USER_DEVICES[$i]}
		[Peer]
		PublicKey = ${user_device_publickeys[$i]}
		AllowedIPs = ${peer_allowed_ips[$i]::-1}
		PersistentKeepalive = 25
		EOF
		)
		Peers+=$peer$'\n\n'
	done

	
	# Needs to configure the priority of the user_device table higher than the gateway tunnel table
	#   because by default the signaficant route 10.1.0.1/24 is lay on the main table, causing the  
	#   user device cannot connect to each other.
	tee /etc/wireguard/user_device.conf.all <<-EOF >/dev/null
	[Interface]
	Address = $server_ip_address_for_user_device/$user_device_subnet_prefix
	ListenPort = $INTERFACE_USER_DEVICE_LISTEN
	PrivateKey = $server_privatekey
	Table = off
	PostUp = ip route add $USER_DEVICE_SUBNET dev %i table $KNOWN_DEVICES_TABLE

	$Peers
	EOF
	
	tee /etc/wireguard/user_device.conf.admin <<-EOF >/dev/null
	[Interface]
	Address = $server_ip_address_for_user_device/$user_device_subnet_prefix
	ListenPort = $INTERFACE_USER_DEVICE_LISTEN
	PrivateKey = $server_privatekey
	Table = off
	PostUp = ip route add $USER_DEVICE_SUBNET dev %i table $KNOWN_DEVICES_TABLE

	$(sed '/^$/q' <<< $Peers)

	EOF
	cp /etc/wireguard/user_device.conf.admin /etc/wireguard/user_device.conf
	systemctl enable --now wg-quick@user_device

	echo 'net.ipv4.ip_forward=1' >>/etc/sysctl.d/local.conf
	sysctl --system

	# For the user device to use $HOSTNAME.$DOMAIN as the endpoint
	vpn-update-self-dns-record
}

vpn_cron () {
	tee /etc/cron.d/vpn <<-EOF >/dev/null
	PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	MAILTO=''

	* * * * * root random-sleep 30 && vpn-update-self-dns-record

	$vpn_crons
	EOF
}
