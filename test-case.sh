#!/bin/bash

# Raw terminal and putty cannot display ✔ and ✘ because of no compatible font.

set -u -o pipefail

shopt -s expand_aliases
alias ssh='ssh -o ConnectTimeout=4'

source env.sh

declare passed=0 failed=0

function pass () {
	echo "✔ Pass, $test_name"
	let passed++
	log
}

function fail () {
	echo "✘ Fail, $test_name"
	let failed++
	log
}

function log () {
	echo -e "$test_name\n\n$log_text\n\n\n\n\n" >>/root/test_case_summary
}

echo >>/root/test_case_summary

echo -e "System test"
# Network
test_name="IP address is static and correct"
log_text=$(ip a) &&
[[ ! $log_text =~ 'dynamic' ]] &&
[[ $log_text =~ "$IP_ADDRESS" ]] &&
pass || fail

# Apt
# `apt-get upgrade --assume-no` will return non-zero if there are package need to upgrade
test_name="The apt repositories are set and the system is up to date"
log_text=$(apt-get update && apt-get upgrade --assume-no) &&
[[ $log_text =~ "$DEBIAN_MIRROR" ]] &&
pass || fail

# CA certificates
test_name="Only chosen CA certificates are trusted"
log_text=$(ls /etc/ssl/certs) &&
[[ ! $log_text =~ ('CFCA'|'Hongkong'|'GDCA') ]] &&
[[ $log_text =~ 'ISRG' ]] &&
pass || fail

# Locale
test_name="LANG=en_HK.UTF-8"
log_text=$(locale) &&
[[ $log_text =~ 'LANG=en_HK.UTF-8' ]] &&
pass || fail

# Hostname
test_name="Hostname is set"
log_text=$(hostname) &&
[[ $log_text =~ "$HOSTNAME" ]] &&
pass || fail

# Time zone
test_name="Time zone is set"
log_text=$(timedatectl) &&
[[ $log_text =~ 'Time zone: Asia/Hong_Kong' ]] &&
pass || fail

# SSH
test_name="Root's SSH key pair is generated"
log_text=$(ls /root/.ssh) &&
[[ $log_text =~ 'id_ed25519' ]] &&
pass || fail

# Kernel
test_name="IPv6 is disabled"
log_text=$(ip a) &&
[[ ! $log_text =~ 'inet6' ]] &&
pass || fail

test_name="Transparent HugePage is set to madvise"
log_text=$(cat /sys/kernel/mm/transparent_hugepage/enabled) &&
[[ $log_text =~ '[madvise]' ]] &&
pass || fail

test_name="The kernel overcommit memory setting is set to 1"
log_text=$(sysctl -a | grep vm.overcommit_memory) &&
[[ $log_text =~ 'vm.overcommit_memory = 1' ]] &&
pass || fail


## USER
echo -e "\n\nUser test"

# dnscrypt-proxy
test_name="dnscrypt-proxy is running and have no warning"
log_text=$(systemctl status dnscrypt-proxy.service) &&
[[ ! $log_text =~ 'WARNING' ]] &&
pass || fail

# The `grep dnscrypt-proxy` will return non-zero if it cannot find any match,
# 	so this test will fail even the system have not installed dnscrypt-proxy.
test_name="dnscrypt-proxy.socket and dnscrypt-proxy-resolvconf are not running"
log_text=$(systemctl list-units --state=active | grep dnscrypt-proxy) &&
[[ ! $log_text =~ ('dnscrypt-proxy.socket'|'dnscrypt-proxy-resolvconf') ]] &&
pass || fail

test_name="System DNS configuration is set to 127.0.0.1"
log_text=$(cat /etc/resolv.conf) &&
[[ $log_text =~ ^'nameserver 127.0.0.1'$ ]] &&
pass || fail

# Apache2
test_name="The Apache2 is running normally."
log_text=$(systemctl status apache2) &&
[[ ! $log_text =~ ('warn'|'error'|'crit'|'alert'|'emerg') ]] &&
pass || fail

# ZFS
test_name="The zpool is normal"
log_text=$(zpool status tank) &&
[[ $log_text =~ 'state: ONLINE' ]] &&
pass || fail

test_name="The required file system are created"
log_text=$(zfs get mountpoint tank/owncloud_data tank/postgresql_data tank/letsencrypt tank/syncthing) &&
pass || fail

# Backup suite - Rclone
test_name="Backup suite - Rclone is installed"
log_text=$(rclone version) &&
pass || fail

# Backup suite - Restic
test_name="Backup suite - Restic is installed"
log_text=$(restic version) &&
pass || fail

# ownCloud
test_name="ownCloud is installed"
log_text=$(sudo -u www-data php /var/www/owncloud/occ status) &&
[[ $log_text =~ 'installed: true' ]] &&
pass || fail

# Certbot (Let's Encrypt)
test_name="At least one certificate request is success"
log_text=$(certbot -q certificates) &&
[[ ! $log_text =~ 'No certificates found' ]] &&
pass || fail

# Collabora Online
test_name="Collabora Online is running normally."
log_text=$(curl -f --no-progress-meter http://127.0.0.1:9980) &&
pass || fail

##################
#### VPS Test ####
##################

# echo -e "\n\nVPS Test, with:\n\tVPS_TUNNEL_SUBNET=10.0.0.0/30"

# SSH
# test_name="VPS - Can connect to the vps instance through SSH"
# log_text=$(ssh 10.0.0.1 exit) &&
# pass || fail

# Apt
# test_name="VPS - The apt repositories is normal and the system is up to date"
# log_text=$(ssh 10.0.0.1 'apt-get update && apt-get upgrade --assume-no') &&
# pass || fail

# HAProxy
# test_name="VPS - HAProxy is running"
# log_text=$(ssh 10.0.0.1 systemctl status haproxy) &&
# pass || fail

# Port Forwarding
# test_name="VPS - Port Forwarding is working"
# public_ip_address=$(dig @1.1.1.1 +short owncloud.$DOMAIN) &&
# log_text=$(curl -f --no-progress-meter --connect-timeout 5 --resolve notexist:80:$public_ip_address http://notexist/ok.html) &&
# [[ $log_text = 'ok' ]] &&
# pass || fail

# CA certificates
# test_name="VPS - Only chosen CA certificates are trusted"
# log_text=$(ssh 10.0.0.1 ls /etc/ssl/certs) &&
# [[ ! $log_text =~ ('CFCA'|'Hongkong'|'GDCA') ]] &&
# [[ $log_text =~ 'ISRG' ]] &&
# pass || fail

# Time zone
# test_name="VPS - Time zone is set"
# log_text=$(ssh 10.0.0.1 timedatectl) &&
# [[ $log_text =~ 'Time zone: Asia/Hong_Kong' ]] &&
# pass || fail

##################
#### DNS Test ####
##################

# test_name="DNS record of all services are set"
# gateway_pubkey=$(ssh 10.0.0.1 wg show wg0 public-key) && \
# mypubkey=$(wg show wg0 public-key) && \
# gateway_ip_address=$(wg show wg0 endpoints | awk -v "gateway_pubkey=$gateway_pubkey" '{if ($1==gateway_pubkey) {print $2}}' | awk -F: '{print $1}') && \
# my_ip=$(ssh 10.0.0.1 'wg show wg0 endpoints' | awk -v "mypubkey=$mypubkey" '{if ($1==mypubkey) {print $2}}' | awk -F: '{print $1}') && \
# [[ $(dig @1.1.1.1 owncloud.$DOMAIN +short) = "$gateway_ip_address" ]] && \
# [[ $(dig @1.1.1.1 collaboraonline.$DOMAIN +short) = "$gateway_ip_address" ]] && \
# [[ $(dig @1.1.1.1 $HOSTNAME.$DOMAIN +short) = "$my_ip" ]] && \
# [[ $(dig @127.0.0.1 owncloud.$DOMAIN +short) = '10.0.0.129' ]] && \
# [[ $(dig @127.0.0.1 collaboraonline.$DOMAIN +short) = '10.0.0.129' ]] && \
# log_text='' && \
# pass || fail

echo -e "\n\nVPS + Local Test, with:\n\tVPS_TUNNEL_SUBNET=10.0.0.0/30\n\tUSER_DEVICE_SUBNET=10.1.0.0/24"

# DNS
# test_name="VPS + Local - DNS record of all services are set"
# vps_ip_address=$(ssh 10.0.0.1 curl -4 -f --no-progress-meter https://icanhazip.com) &&
# my_ip=$(curl -f --no-progress-meter https://icanhazip.com) &&
# [[ $(dig @1.1.1.1 owncloud.$DOMAIN +short) = "$vps_ip_address" ]] &&
# [[ $(dig @1.1.1.1 collaboraonline.$DOMAIN +short) = "$vps_ip_address" ]] &&
# [[ $(dig @1.1.1.1 $HOSTNAME.$DOMAIN +short) = "$my_ip" ]] &&
# [[ $(dig @127.0.0.1 owncloud.$DOMAIN +short) = "$VIRTUAL_IP_ADDRESS" ]] &&
# [[ $(dig @127.0.0.1 collaboraonline.$DOMAIN +short) = "$VIRTUAL_IP_ADDRESS" ]] &&
# [[ $(dig @127.0.0.1 syncthing.$DOMAIN +short) = "$VIRTUAL_IP_ADDRESS" ]] &&
# log_text='' &&
# pass || fail

# DNS
test_name="DNS record of all services are set"
my_ip=$(curl -f --no-progress-meter https://icanhazip.com) &&
[[ $(dig @1.1.1.1 $HOSTNAME.$DOMAIN +short) = "$my_ip" ]] &&
[[ $(dig @127.0.0.1 owncloud.$DOMAIN +short) = "$VIRTUAL_IP_ADDRESS" ]] &&
[[ $(dig @127.0.0.1 collaboraonline.$DOMAIN +short) = "$VIRTUAL_IP_ADDRESS" ]] &&
[[ $(dig @127.0.0.1 syncthing.$DOMAIN +short) = "$VIRTUAL_IP_ADDRESS" ]] &&
[[ $(dig @127.0.0.1 vaultwarden.$DOMAIN +short) = "$VIRTUAL_IP_ADDRESS" ]] &&
log_text='' &&
pass || fail

# Manual Check
# 1. Sucessful ownCloud backup. Modify cron.d/owncloud-backup
#      Verify by `less /var/log/owncloud-backup`, `restic snapshots`, and restore the backup
# 2. Sucessful certbot backup. Modify cron.d/certbot-backup and random-sleep 1
#      Verify by `less /var/log/certbot-backup`, `restic snapshots`, and restore the backup
# 3. ownCloud-backup and certbot-backup will retry until success and not causing collision dead lock when
#      the repository is locked due to the last backup not yet finished.
#      Verify by `restic check --read-data --limit-download 50`, modify the cron time
# 4. owncloud-backup and certbot-backup concurrently start should be collision once only
# 5. When owncloud-backup interrupted, the zfs snapshots and directory will be cleanup.
#      Hit CTRL-C during owncloud-backup.
#      Verify by `zfs list -t all` should be snapshots and `ls /mnt` should be empty
# 6. Sucessful ownCloud restore. Change something and then restore.
# 7. Sucessful certbot restore. Delete /etc/letsencrypt, restart apache2 to fail, then restore it.
# 8. Only one instance of owncloud-backup or certbot-backup at any time. Manually run one of these,
#      expected to CRON will exit.
#      Verify by `less /var/log/owncloud-backup`

# TODO - Daily check DNS filter have updated.
# TODO - external test, ping rpi1.local
echo -e "\n\nTest complete:"
echo "$passed of tests passed, $failed of tests failed."
