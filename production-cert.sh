#!/bin/bash

# Ref:
# https://eff-certbot.readthedocs.io/en/stable/using.html?highlight=renew#modifying-the-renewal-configuration-of-existing-certificates

set -eu -o pipefail

BASE=$(dirname $(readlink -f $0))
source $BASE/profiles.sh
source $BASE/env.sh
source $BASE/lib/helpers.sh

runasroot

# certbot renew --server https://acme-v02.api.letsencrypt.org/directory --dry-run

echo 'Do you want to replace your test cert with a production cert?'
select choice in 'yes' 'no'; do
	case $choice in
		yes )
			echo "Getting production cert..."
			certbot renew --cert-name $DOMAIN --server https://acme-v02.api.letsencrypt.org/directory --force-renewal \
			  --dns-cloudflare-propagation-seconds 60 -m "$EMAIL" --agree-tos --no-eff-email \
			  --post-hook="systemctl restart apache2"
			
			certbot renew --cert-name public.$DOMAIN --server https://acme-v02.api.letsencrypt.org/directory --force-renewal \
			  --dns-cloudflare-propagation-seconds 60 -m "$EMAIL" --agree-tos --no-eff-email \
			  --post-hook="systemctl restart dovecot postfix"
			
			echo "Let's Encrypt test cert will be removed for ownCloud also."
			# The existing permission of ca-bundle.crt is preserved.
			# This is a cp behavior when the destination file is already exist
			cp /etc/ssl/certs/ca-certificates.crt /var/www/owncloud/resources/config/ca-bundle.crt
			break
			;;
		no )
			echo "Exit."
			break
			;;
	esac
done
