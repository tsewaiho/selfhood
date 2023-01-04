#############################
#### Basic configuration ####
#############################


#### Profile ####
# Choose a pre-defined profile (vbox or rpi), or define your own in profiles.sh.
PROFILE='vbox'



#### System ####
HOSTNAME='rpi1'
IP_ADDRESS='192.168.1.129/24'
GATEWAY='192.168.1.1'

# Locale
# /usr/share/i18n/SUPPORTED
# (only specify the first colume, the second colume is the charset according to `man locale.gen`)
LOCALE='en_HK.UTF-8'

# Timezone
# /usr/share/zoneinfo
TIMEZONE='Asia/Hong_Kong'



#### User ####

# Master password for restic and WireGuard key derivation (minimum 8 characters)
MASTER_PASSWORD=''

CLOUDFLARE_API_Token=''

SSH_KEY=''

DOMAIN='example.com'
EMAIL='admin@example.com'

HETZNER_API_TOKEN=''



################################
#### Advanced configuration ####
################################

# https://www.debian.org/mirror/list
# DEBIAN_MIRROR='http://mirror.xtom.com.hk'
DEBIAN_MIRROR='http://deb.debian.org'


RESTIC_REPOSITORY='rclone:remote:.rclone/.restic'

VIRTUAL_IP_ADDRESS='10.10.10.10'

VPS_TUNNEL_SUBNET='10.0.0.0/30'
VPS_INTERFACE_TABLE='150'
VPS_INTERFACE_TABLE_PRIORITY='15000'

HETZNER_SERVER_LOCATION='fsn1'
HETZNER_SERVER_IP_ADDRESS=''

KNOWN_DEVICES_TABLE='100'
KNOWN_DEVICES_PRIORITY='10000'
USER_DEVICE_SUBNET='10.1.0.0/24'
INTERFACE_USER_DEVICE_LISTEN='51820'
USER_DEVICES=('windows.laptop' 'windows.desktop' 'mobile' 'tablet')
GATEWAY_TABLE_START_FROM='200'
GATEWAY_PRIORITY='20000'
PLACEHOLDER_SUBNET='10.255.255.0/24'
DOCKER_SUBNET_WITH_VPN='172.18.0.0/16'
DOCKER_SUBNET_WITH_VPN_NULL_ROUTE_TABLE='252'
DOCKER_SUBNET_WITH_VPN_NULL_ROUTE_PRIORITY='32765'

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

# ZRAM size
ZRAM_SIZE='6G'
