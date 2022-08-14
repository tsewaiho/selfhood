echo 'DPkg::Lock::Timeout 60;' >>/etc/apt/apt.conf.d/70debconf
tee /etc/apt/sources.list <<EOF >/dev/null
deb http://deb.debian.org/debian bullseye main
deb http://security.debian.org/debian-security bullseye-security main
deb http://deb.debian.org/debian bullseye-updates main
deb http://deb.debian.org/debian bullseye-backports main contrib
EOF
apt-get update
apt-get -y full-upgrade
apt-get -y autoremove

apt-get install -y linux-headers-cloud-amd64
apt-get install -y ca-certificates wireguard-tools nftables wget
apt-get install -t bullseye-backports -y curl
# apt-get install -t bullseye-backports -y haproxy

tee /etc/ca-certificates.conf <<EOF >/dev/null
# GlobalSign - Japan
# pypi.org
mozilla/GlobalSign_Root_CA_-_R3.crt

# Amazon - United States (Amazon purchased Starfield Services Root Certificate Authority - G2)
# aws.amazon.com, download.docker.com
mozilla/Amazon_Root_CA_1.crt
mozilla/Starfield_Services_Root_Certificate_Authority_-_G2.crt

# Internet Security Research Group - United States (Let's Encrypt)
# owncloud.com, nextcloud.com, rclone.org, restic.net, protonvpn.com, collaboraoffice.com
mozilla/ISRG_Root_X1.crt

# DigiCert - United States (DigiCert purchased QuoVadis and Baltimore CyberTrust Root)
# pcloud.com, github.com, packages.microsoft.com, api.hetzner.cloud, repo.protonvpn.com
mozilla/QuoVadis_Root_CA_2.crt
mozilla/DigiCert_High_Assurance_EV_Root_CA.crt
mozilla/DigiCert_Global_Root_G2.crt
mozilla/DigiCert_Global_Root_CA.crt
mozilla/Baltimore_CyberTrust_Root.crt
EOF
update-ca-certificates --fresh

timedatectl set-timezone $TIMEZONE


tee /etc/wireguard/home_server.conf <<EOF >/dev/null
[Interface]
Address = $vps_wg_ip_address/30
ListenPort = 51820
PrivateKey = $vps_privatekey

[Peer]
PublicKey = $home_server_publickey
AllowedIPs = $home_server_wg_ip_address/32
EOF
systemctl enable --now wg-quick@home_server

# https://www.haproxy.com/blog/multithreading-in-haproxy/#multithreading-configuration
#
# tee /etc/haproxy/haproxy.cfg <<EOF >/dev/null
# global
# 	nbproc 1
# 	nbthread 2
# 	cpu-map auto:1/1-2 0-1
# defaults
# 	mode tcp
# 	timeout connect 5000
# 	timeout client 50000
# 	timeout server 50000
# listen http
# 	bind :80
# 	server server1 $home_server_wg_ip_address send-proxy-v2
# listen https
# 	bind :443
# 	server server1 $home_server_wg_ip_address send-proxy-v2
# EOF
# systemctl restart haproxy

systemctl enable --now nftables
tee /etc/nftables.conf <<EOF >/dev/null
#!/usr/sbin/nft -f

flush ruleset

table ip filter {
	chain INPUT {
		type filter hook input priority filter; policy drop;
		ct state established,related accept
		iif lo accept
		udp dport {51820} accept
		tcp dport {22,80,443} accept
		# udp dport {53} ip saddr 10.0.0.0/24 accept
		ip saddr $home_server_wg_ip_address/32 accept
	}
	chain FORWARD {
		type filter hook forward priority filter; policy drop;
		ct state established,related accept
		# ip saddr 10.0.0.0/24 accept
		ip daddr $home_server_wg_ip_address/32 accept
	}
}
table ip nat {
	chain PREROUTING {
		type nat hook prerouting priority dstnat;
		fib daddr type local tcp dport {80,443} dnat to $home_server_wg_ip_address
	}
	chain POSTROUTING {
		type nat hook postrouting priority srcnat;
		# ip saddr 10.0.0.0/24 oif eth0 masquerade
	}
}
EOF
nft -f /etc/nftables.conf

echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/local.conf
sysctl --system

## Extra
# Collabora Online
# cd /usr/share/keyrings
# wget -q https://collaboraoffice.com/downloads/gpg/collaboraonline-release-keyring.gpg
# tee /etc/apt/sources.list.d/collaboraonline.sources <<EOF > /dev/null
# Types: deb
# URIs: https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-debian11
# Suites: ./
# Signed-By: /usr/share/keyrings/collaboraonline-release-keyring.gpg
# EOF
# apt-get update
# apt-get install -y coolwsd code-brand
# coolconfig set ssl.enable false
# coolconfig set ssl.termination true
# coolconfig set storage.wopi.host owncloud.$DOMAIN
# coolconfig set server_name collaboraonline.$DOMAIN
# coolconfig set admin_console.enable false
# systemctl restart coolwsd.service
