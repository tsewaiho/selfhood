# Commons for all system
#
# Depended environment variables
#  - IFACE
#  - PROFILE
#  - IP_ADDRESS
#  - GATEWAY
#  - DEBIAN_MIRROR
#  - LOCALE
#  - HOSTNAME
#  - TIMEZONE


# Network
ifdown ${IFACE[$PROFILE]}
tee /etc/network/interfaces <<EOF >/dev/null
auto lo
iface lo inet loopback

source /etc/network/interfaces.d/*
EOF
tee /etc/network/interfaces.d/${IFACE[$PROFILE]} <<EOF >/dev/null
allow-hotplug ${IFACE[$PROFILE]}
iface ${IFACE[$PROFILE]} inet static
	address $IP_ADDRESS
	gateway $GATEWAY
EOF
ifup ${IFACE[$PROFILE]}


# Debian repository
# 'DPkg::Lock::Timeout' add auto-retry to due with the apt-daily-upgrade.service interfere
echo 'DPkg::Lock::Timeout 60;' >>/etc/apt/apt.conf.d/70debconf
tee /etc/apt/sources.list <<EOF >/dev/null
deb $DEBIAN_MIRROR/debian bullseye main
deb http://security.debian.org/debian-security bullseye-security main
deb $DEBIAN_MIRROR/debian bullseye-updates main
deb $DEBIAN_MIRROR/debian bullseye-backports main contrib
EOF
apt-get update
apt-get upgrade -y
apt-get autoremove -y


# Software
apt-get install -y ca-certificates locales avahi-daemon eject jq wget unzip sudo gpg sed \
	bash-completion
apt-get install -t bullseye-backports -y curl


# CA certificates
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

# Sectigo - United States
# apt.syncthing.net, dbeaver.io
# https://support.sectigo.com/articles/Knowledge/Sectigo-AddTrust-External-CA-Root-Expiring-May-30-2020
# https://sectigo.com/about/contact
mozilla/USERTrust_ECC_Certification_Authority.crt
mozilla/USERTrust_RSA_Certification_Authority.crt
EOF
update-ca-certificates --fresh


# locale
sed -i "/$LOCALE/s/^#\s*//" /etc/locale.gen
locale-gen
update-locale LANG=$LOCALE


# Hostname
# man hostname
# Have to delete and re-add because the Raspberry Pi version of Debian do not have the 127.0.1.1 line.
hostnamectl set-hostname $HOSTNAME
systemctl restart avahi-daemon
sed -i "/127\.0\.1\.1/d" /etc/hosts
echo -e "127.0.1.1\t$HOSTNAME.$DOMAIN $HOSTNAME" >>/etc/hosts

# Time zone
# /etc/systemd/timesyncd.conf
# On VirtualBox env, systemd-timesyncd is conflict with vboxadd-service, so ntp will not be started on boot.
# https://stackoverflow.com/questions/67511592/debugging-systemctl-inactive-dead
timedatectl set-timezone $TIMEZONE


# SSH
ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"


# ZRAM
if [[ $ZRAM_SIZE != "0" ]]; then
	echo 'zram' >/etc/modules-load.d/zram.conf
	tee /etc/udev/rules.d/99-zram.rules <<-EOF
	KERNEL=="zram0", SUBSYSTEM=="block", ACTION=="add", ATTR{comp_algorithm}="zstd", ATTR{disksize}="$ZRAM_SIZE", RUN="/usr/sbin/mkswap /dev/zram0"
	EOF
	tee -a /etc/sysctl.d/local.conf <<-EOF
	vm.page-cluster = 0
	vm.swappiness = 200
	vm.vfs_cache_pressure = 500
	vm.dirty_background_ratio = 2
	EOF
	sed -i -E '/^[^[:space:]#]+[[:space:]]+[^[:space:]]+[[:space:]]+swap/s/^/#/' /etc/fstab

	tee -a /etc/fstab <<-EOF
	/dev/zram0 none swap defaults 0 0
	EOF
fi



# Kernel
#  - ipv6
#      (ipv6.disable will cause some software report Address family not supported by protocol, use ipv6.disable_ipv6 instead)
#  - transparent hugepages (required by Redis)
#  - overcommit_memory (required by Redis)
# https://redis.io/docs/manual/admin/#redis-setup-hints
if [ -f "/etc/default/grub" ]; then
	sed -i '/GRUB_CMDLINE_LINUX=/c GRUB_CMDLINE_LINUX="ipv6.disable_ipv6=1 transparent_hugepage=madvise"' /etc/default/grub
	update-grub
elif [ -f "/boot/firmware/cmdline.txt" ]; then
	sed -i 's/$/ipv6.disable_ipv6=1 transparent_hugepage=madvise /' /boot/firmware/cmdline.txt
fi
echo 'vm.overcommit_memory = 1' >>/etc/sysctl.d/local.conf
sysctl --system

# Raspberry Pi
if [ -f "/boot/firmware/config.txt" ]; then
	echo 'gpu_mem=16' >/boot/firmware/config.txt
fi
