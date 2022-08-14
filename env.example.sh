#############################
#### Basic configuration ####
#############################


#### Profile ####
# Choose a pre-defined profile (vbox or rpi), or define your own in profiles.sh.
PROFILE=vbox



#### System ####
HOSTNAME=rpi1
IP_ADDRESS=192.168.1.129/24
GATEWAY=192.168.1.1

# Locale
# /usr/share/i18n/SUPPORTED
# (only specify the first colume, the second colume is the charset according to `man locale.gen`)
LOCALE=en_HK.UTF-8

# Timezone
# /usr/share/zoneinfo
TIMEZONE=Asia/Hong_Kong



#### User ####

# Master password for restic and WireGuard key derivation (minimum 8 characters)
MASTER_PASSWORD=

CLOUDFLARE_API_Token=

SSH_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEy0WBEwTHEuwMIcNsfbvULl+m49HXD8f5h/HRohzu0W eddsa-key-20220814'

DOMAIN=example.com
EMAIL=admin@example.com

# Not used in current version.
# HCLOUD_API_TOKEN=



################################
#### Advanced configuration ####
################################

# https://www.debian.org/mirror/list
# DEBIAN_MIRROR=http://mirror.xtom.com.hk
DEBIAN_MIRROR=http://deb.debian.org


RESTIC_REPOSITORY='rclone:remote:.rclone/.restic'

VIRTUAL_IP_ADDRESS=10.10.10.10

# Not used in current version.
# VPS_TUNNEL_SUBNET=10.0.0.0/30
# VPS_INTERFACE_TABLE=150
# VPS_INTERFACE_TABLE_PRIORITY=25000

USER_DEVICE_SUBNET=10.1.0.0/24
USER_DEVICE_TABLE=100
USER_DEVICE_TABLE_PRIORITY=30000
INTERFACE_USER_DEVICE_LISTEN=51820
USER_DEVICES=(mobile tablet laptop windows.desktop)
GATEWAY_TABLE_START_FROM=200
PLACEHOLDER_SUBNET=10.255.255.0/24

# Subscribed VPN service tunnel
# credentials/wg_config_files
#
# The interface naming constraint is [a-zA-Z0-9_=+.-]{1,15}
# The maximum length of the interface name is 15 characters.
# https://git.zx2c4.com/wireguard-tools/about/src/man/wg-quick.8
#
# ProtonVPN will regularly maintenance their server. The maintenance will bring down all VPN nodes in the
#   same domain, so you should choose the VPN nodes from different domain.
#   You can check the domain of the VPN node at https://api.protonmail.ch/vpn/logicals
