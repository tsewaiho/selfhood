#!/bin/bash

# Environment variables
#  - USER_DEVICE_SUBNET
#  - DISK1
#  - DISK2
#  - PROFILE
#  - vps_ip_address
#  - DOMAIN

set -eu -o pipefail

BASE=$(dirname $(readlink -f $0))
source $BASE/profiles.sh
source $BASE/env.sh
source $BASE/lib/helpers.sh

runasroot

source $BASE/lib/cloudflare.sh
# source $BASE/lib/hetzner.sh


# Mode
mode=''
echo 'Select mode:'
while [ -z "$mode" ]; do
	select choice in 'new-installation' 'restore-from-disk' 'restore-from-restic'; do
		mode=$choice
		break
	done
done

# Restic and Rclone
source $BASE/components/backup_restore_suite.sh

if [ $mode = 'restore-from-restic' ]; then
	until snapshots_json=$(restic snapshots --tag full --json) && jq -e 'any' <<<$snapshots_json; do
		echo 'Your restic repository is either have issue or have no snapshot.'
		echo 'You can troubleshoot yourself on another vty and retry, or exit'
		select choice in 'retry' 'exit'; do
			case $choice in
				retry )
					echo "Retry..."
					break
					;;
				exit )
					echo "The installation is stopped."
					exit 1
					;;
			esac
		done
	done

	snapshots=$(restic snapshots --tag full)
	snapshot_id=''
	until [ "$snapshot_id" = 'latest' ] ||
	  jq -e --arg id "$snapshot_id" 'map(select(.short_id == $id)) | any' <<<$snapshots_json >/dev/null
	do
		echo "$snapshots"
		echo 'Select snapshot:'
		select choice in 'latest' $(jq -r '.[].short_id' <<<$snapshots_json); do
			snapshot_id=$choice
			break
		done
	done
fi


# Install bin and lib
cp $BASE/bin/* /usr/local/bin/
chmod 755 /usr/local/bin/*

cp $BASE/lib/cloudflare.sh /usr/local/lib/
mkdir -p $HOME/.config/cloudflare
echo "CLOUDFLARE_API_Token=$CLOUDFLARE_API_Token" >$HOME/.config/cloudflare/cloudflare.sh

# ZFS
source $BASE/components/zfs.sh
zfs_install


# Firewall
# https://wiki.nftables.org/wiki-nftables/index.php/Netfilter_hooks
systemctl enable --now nftables
tee /etc/nftables.conf <<EOF >/dev/null
#!/usr/sbin/nft -f

flush ruleset

table ip filter {
	chain STRONG {
		type filter hook input priority raw;
		ip saddr $USER_DEVICE_SUBNET iifname != "user_device" drop
		ip saddr 172.17.0.0/16 iifname != "docker0" drop
	}
	chain INPUT {
		type filter hook input priority filter; policy drop;
		ct state established,related accept
		iif lo accept
		udp dport {$INTERFACE_USER_DEVICE_LISTEN,mdns} accept
		tcp dport {22} accept
		udp dport {53} ip saddr {$USER_DEVICE_SUBNET,172.17.0.1/16} accept
		tcp dport {80,443} ip saddr {$USER_DEVICE_SUBNET,172.17.0.1/16} accept
		# syncthing
		udp dport {22000} ip saddr $USER_DEVICE_SUBNET accept
		tcp dport {22000} ip saddr $USER_DEVICE_SUBNET accept
	}
	chain POSTROUTING {
		type filter hook postrouting priority filter;
		ip saddr $USER_DEVICE_SUBNET oif ${IFACE[$PROFILE]} drop
	}
	# Required even if no rule because of the drop policy
	chain FORWARD {
		type filter hook forward priority filter; policy drop;
		ct state established,related accept
		# ip saddr 10.0.0.128/25 accept
	}
}

table ip nat {
	chain POSTROUTING {
		type nat hook postrouting priority srcnat;
		#ip saddr 10.0.0.128/25 oifname "wg1" masquerade
	}
}
EOF
nft -f /etc/nftables.conf


# DNS
source $BASE/components/dnscrypt-proxy.sh
dnscrypt_proxy_install
echo 'nameserver 127.0.0.1' >/etc/resolv.conf


# VPS (for external services)
# source $BASE/components/vps/vps.sh
# vps_install

# Setup VPN services for user devices
source $BASE/components/vpn/vpn.sh
vpn_install

# Certbot
source $BASE/components/certbot/certbot.sh
certbot_install

# Reverse proxy
source $BASE/components/reverse_proxy.sh
reverse_proxy_install

# Virtual IP address
tee /etc/network/interfaces.d/du0 <<-EOF >/dev/null
auto du0
iface du0 inet static
  address $VIRTUAL_IP_ADDRESS/32
  pre-up ip link add du0 type dummy
  post-down ip link del du0
EOF
ifup du0

# Set HOSTS for VPN client (bypass HAProxy)
tee /etc/dnscrypt-proxy/cloaking-rules.txt <<EOF >/dev/null
=owncloud.$DOMAIN $VIRTUAL_IP_ADDRESS
=collaboraonline.$DOMAIN $VIRTUAL_IP_ADDRESS
=syncthing.$DOMAIN $VIRTUAL_IP_ADDRESS
=vaultwarden.$DOMAIN $VIRTUAL_IP_ADDRESS
EOF
systemctl restart dnscrypt-proxy.service
dnscrypt_proxy_wait


# Update the DNS record of all website's domain to the VPS IP address
# cloudflare_dns_update 'owncloud' $DOMAIN $vps_ip_address
# cloudflare_dns_update 'collaboraonline' $DOMAIN $vps_ip_address

# Docker
source $BASE/components/docker.sh

# Php
source $BASE/components/php.sh

# Database
source $BASE/components/database.sh

# ownCloud
source $BASE/components/owncloud/owncloud.sh

# Syncthing
source $BASE/components/syncthing.sh
syncthing_install

# vaultwarden
source $BASE/components/vaultwarden.sh
vaultwarden_install

# Create or restore filesystem
# Use underscore on multiwords, https://docs.oracle.com/cd/E19253-01/819-5461/gamnn/index.html
declare -A zfs_filesystem
zfs_filesystem['tank/owncloud_data']='/var/lib/owncloud'
zfs_filesystem['tank/postgresql_data']='/var/lib/postgresql/13/main'
zfs_filesystem['tank/letsencrypt']='/etc/letsencrypt'
zfs_filesystem['tank/syncthing']='/var/lib/syncthing'
zfs_filesystem['tank/vaultwarden']='/var/lib/vaultwarden'

systemctl stop apache2.service
systemctl stop php7.4-fpm.service
systemctl stop postgresql@13-main.service
systemctl stop syncthing@syncthing.service
docker stop vaultwarden
redis-cli <<<"FLUSHALL"

if [ $mode = 'new-installation' ]; then
	zfs_create_zpool
	for name in ${!zfs_filesystem[@]}; do
		zfs_create_filesystem_with_data $name ${zfs_filesystem[$name]}
	done
elif [ $mode = 'restore-from-disk' ]; then
	zfs_import_zpool
	for name in ${!zfs_filesystem[@]}; do
		zfs_create_filesystem_with_data $name ${zfs_filesystem[$name]}
	done
elif [ $mode = 'restore-from-restic' ]; then
	zfs_create_zpool
	for name in ${!zfs_filesystem[@]}; do
		snapshot_ls=$(restic ls -q $snapshot_id ${zfs_filesystem[$name]})
		if [ -z "$snapshot_ls" ]; then
			zfs_create_filesystem_with_data $name ${zfs_filesystem[$name]}
		else
			zfs create -o mountpoint=${zfs_filesystem[$name]} $name
		fi
	done
	restic restore --tag full --target / --verify $snapshot_id
fi

docker start vaultwarden
systemctl start syncthing@syncthing.service
systemctl start postgresql@13-main.service
systemctl start php7.4-fpm.service
sudo -u www-data php /var/www/owncloud/occ maintenance:data-fingerprint <<<'yes'
systemctl start apache2.service


# Access control
# apt-get install -y sudo
# useradd -m -s /bin/bash admin
# chpasswd <<<"admin:$MASTER_PASSWORD"
# usermod -aG sudo admin
# passwd -l root
echo "$SSH_KEY" >/root/.ssh/authorized_keys
tee /root/ssh_fingerprint.txt <<EOF
$(ssh-keygen -l -E md5    -f /etc/ssh/ssh_host_ecdsa_key)
$(ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_ecdsa_key)
$(ssh-keygen -l -E md5    -f /etc/ssh/ssh_host_ed25519_key)
$(ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_ed25519_key)
$(ssh-keygen -l -E md5    -f /etc/ssh/ssh_host_rsa_key)
$(ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_rsa_key)
EOF

# Version
echo 'v0.1.0' >/tank/version

## CRONJOBS ##
zfs_cron
dnscrypt_proxy_cron
vpn_cron
certbot_cron
owncloud_cron

tee /etc/cron.d/backup <<-EOF >/dev/null
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

#55 * * * * root backup-full cron >>/var/log/backup-full 2>&1
EOF

echo -e "\nInstallation complete."
