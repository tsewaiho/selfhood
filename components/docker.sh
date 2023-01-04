# Docker
# By default, when using the ip rule from 172.18.0.0/16 lookup the ProtonVPN route, reverse proxy won't work.
# Because the host will use 172.18.0.1 as the client ip address to request backend, and 172.18.0.1 will then
# routed to ProtonVPN.

apt-get install -y wget gpg ipcalc-ng
wget -O- https://download.docker.com/linux/debian/gpg | gpg --dearmor >/usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] http://download.docker.com/linux/debian $(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce

docker_subnet_with_vpn_gateway=$(ipcalc-ng --minaddr --no-decorate $DOCKER_SUBNET_WITH_VPN)

docker network create \
  --driver=bridge \
  --subnet=$DOCKER_SUBNET_WITH_VPN \
  --gateway=$docker_subnet_with_vpn_gateway \
  -o 'com.docker.network.bridge.name=docker_vpn' \
  -o 'com.docker.network.bridge.enable_ip_masquerade=false' \
  docker_vpn


tee /etc/systemd/system/docker_routing_table.service <<-EOF >/dev/null
[Unit]
Description=Add custom docker network to the known devices routing table
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=ip route add $DOCKER_SUBNET_WITH_VPN dev docker_vpn table $KNOWN_DEVICES_TABLE

[Install]
WantedBy=multi-user.target
EOF


tee /etc/systemd/system/docker_vpn_subnet_null_route.service <<-EOF >/dev/null
[Unit]
Description=Fast fail response to docker container when all gateway are failed
After=network-online.target
Wants=network-online.target
Before=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=ip rule add from $DOCKER_SUBNET_WITH_VPN lookup $DOCKER_SUBNET_WITH_VPN_NULL_ROUTE_TABLE priority $DOCKER_SUBNET_WITH_VPN_NULL_ROUTE_PRIORITY ; \\
	ip route add prohibit default table $DOCKER_SUBNET_WITH_VPN_NULL_ROUTE_TABLE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now docker_routing_table
systemctl enable --now docker_vpn_subnet_null_route
