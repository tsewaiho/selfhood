# Certbot
#
# Environment variables
#  - CLOUDFLARE_API_Token

certbot_install () {
	# Let's Encrypt
	# Do not subscribe to EFF because sometimes it will have below error due to subscription API down.
	#   "We were unable to subscribe you the EFF mailing list because your e-mail address appears to be invalid"
	# https://github.com/certbot/certbot/issues/8973
	apt-get install -y python3-venv
	python3 -m venv /opt/certbot
	/opt/certbot/bin/pip install --upgrade pip
	/opt/certbot/bin/pip install wheel
	/opt/certbot/bin/pip install certbot
	/opt/certbot/bin/pip install certbot-dns-cloudflare
	ln -sf /opt/certbot/bin/certbot /usr/bin/certbot
	mkdir -p $HOME/.config/certbot
	echo "dns_cloudflare_api_token = $CLOUDFLARE_API_Token" >$HOME/.config/certbot/cloudflare.ini
	chmod 400 $HOME/.config/certbot/cloudflare.ini
}

certbot_get_cert () {
	local name=$1 domain=$2 email=$3
	until certbot certonly --test-cert \
		--dns-cloudflare --dns-cloudflare-credentials $HOME/.config/certbot/cloudflare.ini \
		--key-type ecdsa --elliptic-curve secp384r1 --must-staple \
		--cert-name "$name" -d "$domain" -m "$email" \
		--agree-tos --no-eff-email
	do
		echo "Let's Encrypt certificate request is failed, choose what to do."
		select choice in 'retry' 'exit'; do
			case $choice in
				retry )
					echo "retry"
					break
					;;
				exit )
					echo "The installation is stopped."
					exit 1
					;;
			esac
		done
	done
}

# The Let's Encrypt certificate has 90 days lifetime, the official recommend renewing certificate every 60 days.
# I will make the automatic renew run on every Sunday, and then backup it after that no matter whether
# the certificate is renewed.
certbot_cron () {
	tee /etc/cron.d/certbot <<-EOF >/dev/null
	PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	0 0 * * 0 root random-sleep 1800 && certbot renew -q
	EOF
}
