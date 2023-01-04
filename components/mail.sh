# Mail Server
#
# Environment variables
#  - DOMAIN
#  - home_server_wg_ip_address

mail_install () {
	local hostname="public.$DOMAIN"

	# Mail certificate
	certbot_get_cert "$hostname" "$hostname" "$EMAIL" false

	# Mail DNS
	cloudflare_dns_update "$DOMAIN" 'MX' '@' "$hostname"
	cloudflare_dns_update "$DOMAIN" 'TXT' '@' 'v=spf1 mx ~all'
	cloudflare_dns_update "$DOMAIN" 'TXT' 'public' "v=spf1 a ~all"

	# Other necessary SPF
	# http://www.open-spf.org/action_browse_id_FAQ/Common_mistakes_revision_26/#helo
	cloudflare_dns_update "$DOMAIN" 'TXT' "$HOSTNAME" "v=spf1 -all"

	#### Transmit ##################
	#### Postfix configurations ####
	#
	# postconf support two format, quoted or not quoted
	# 
	# Postfix have a sense of origin, main mail domain
	# When specified "postfix/mailname" on Postfix installation, it will
	# write that value to /etc/mailname, and multiple place on main.cf.
	debconf-set-selections <<-EOF
	postfix postfix/mailname string $DOMAIN
	postfix postfix/main_mailer_type string 'Internet Site'
	EOF
	apt-get install -y postfix postfix-sqlite sqlite3 postfix-pgsql dovecot-core dovecot-imapd dovecot-lmtpd dovecot-pgsql

	postconf -e 'inet_protocols = ipv4'

	# This parameter defines the size limit for emails originating from your own mail server and for 
	# emails coming to your mail server. You can not send an attachment larger than 25MB to a Gmail address.
	postconf -e 'message_size_limit = 26214400'

	# The mail server DNS name (MX record)
	postconf -e "myhostname = $hostname"

	# Needed for ip rule to route all out going email to the VPS
	postconf -e "smtp_bind_address = $home_server_wg_ip_address"

	# The preferred way to configure tls key and certificate is "smtpd_tls_chain_files".
	# https://www.postfix.org/postconf.5.html#smtpd_tls_key_file
	postconf -e "smtpd_tls_chain_files = /etc/letsencrypt/live/$hostname/privkey.pem, /etc/letsencrypt/live/$hostname/fullchain.pem"
	postconf -X 'smtpd_tls_cert_file'
	postconf -X 'smtpd_tls_key_file'

	# Enable submission on both port 586 and port 465
	# In master.cf, lines that start with whitespace is continue to previous line.
	# Comment line between options is OK for these two submission daemon
	sed -i '/^#submission inet n/,/^#\S/ {/^#submission inet n/s/^#// ; /^#\s[^\$]*$/s/^#//}' /etc/postfix/master.cf
	sed -i '/^#smtps     inet  n/,/^#\S/ {/^#smtps     inet  n/s/^#// ; /^#\s[^\$]*$/s/^#//}' /etc/postfix/master.cf

	postconf -e 'smtpd_sender_restrictions = reject_authenticated_sender_login_mismatch'
	postconf -e 'smtpd_sender_login_maps = hash:/etc/postfix/sender_login_maps'
	tee /etc/postfix/sender_login_maps <<-EOF
	admin@$DOMAIN admin@$DOMAIN
	vaultwarden@$DOMAIN vaultwarden@$DOMAIN
	me@$DOMAIN me@$DOMAIN
	EOF
	postmap /etc/postfix/sender_login_maps

	# DKIM
	#   https://wiki.debian.org/opendkim
	#   https://manpages.debian.org/bullseye/opendkim-tools/opendkim-genkey.8.en.html
	#   https://wiki.archlinux.org/title/OpenDKIM
	#   It will only verify when signature exist
	#   https://marc.info/?l=postfix-users&m=147787879005637&w=2
	apt-get install -y opendkim
	sudo -u opendkim opendkim-genkey -D /etc/dkimkeys -d $DOMAIN

	local dkim_p
	dkim_p=$(openssl rsa -in /etc/dkimkeys/default.private -pubout -outform DER | base64 -w 0)
	cloudflare_dns_update "$DOMAIN" 'TXT' 'default._domainkey' "v=DKIM1; h=sha256; k=rsa; p=$dkim_p"

	sed -i "/#Domain\s/c Domain $DOMAIN" /etc/opendkim.conf
	sed -i '/#Selector\s/c Selector default' /etc/opendkim.conf
	sed -i '/#KeyFile\s/c KeyFile /etc/dkimkeys/default.private' /etc/opendkim.conf
	sed -i '/local:\/run\/opendkim\/opendkim.sock/s/^/#/' /etc/opendkim.conf
	sed -i '/local:\/var\/spool\/postfix\/opendkim\/opendkim.sock/s/^#//' /etc/opendkim.conf

	usermod -aG opendkim postfix
	mkdir -m u=rwx,g=rx,o= /var/spool/postfix/opendkim
	chown opendkim: /var/spool/postfix/opendkim

	postconf -e 'smtpd_milters = unix:opendkim/opendkim.sock'
	postconf -e 'non_smtpd_milters = $smtpd_milters'
	postconf -e 'internal_mail_filter_classes = bounce'
	postconf -e 'milter_default_action = accept'

	# DMARC
	#   The default value pct is 100. The ideal DMARC record should have no pct tag.
	#   p=reject
	#   rua=mailto:dmarc@$DOMAIN;
	#   rua can be postmaster or dmarc, https://support.google.com/a/answer/10032473?hl=en
	#   v=DMARC1; p=reject; rua=mailto:dmarc@$DOMAIN
	cloudflare_dns_update "$DOMAIN" 'TXT' '_dmarc' "v=DMARC1; p=reject; rua=mailto:dmarc@$DOMAIN"

	#### Receive ####
	# Postfix

	# This parameter control what domain is considered local, and will be processed by the local delivery agent
	postconf -e "mydestination = $DOMAIN, localhost"

	postconf -e 'smtpd_tls_security_level = encrypt'

	# Add the TLS info to "Received" header on receive side (port 25) only
	sed -f- -i /etc/postfix/master.cf <<-'EOF'
	/smtp\s*inet\s*n\s*-\s*y\s*-\s*-\s*smtpd/a \
	  -o smtpd_tls_received_header=yes
	EOF

	# Forward the received email to dovecot lmtp 
	postconf -e 'mailbox_transport = lmtp:unix:private/dovecot-lmtp'
	sed -f- -i /etc/dovecot/conf.d/10-master.conf <<-'EOF'
	/service lmtp {/ a \
	  unix_listener /var/spool/postfix/private/dovecot-lmtp { \
	    mode = 0600 \
	    user = postfix \
	    group = postfix \
	  }
	EOF
	

	# aliases
	#   Run `newaliases` will created a /etc/aliases.db.
	#   This command is necessary each time the /etc/aliases is updated.
	#   The document also stated that the update may delay up to 1 minute,
	#   execute `systemctl reload postfix` to eliminate this delay.
	#
	# https://github.com/mixmaxhq/role-based-email-addresses/blob/master/index.js
	#
	# During postfix installation, a warning is prompt "WARNING: /etc/aliases exists, but does not have a root alias."
	# As crontab will send mail to the root user, and most functional mailname like dmarc is alias to root.
	# I choose to alias root to the admin of my main domain, because admin is the default name most app.
	
	# The default postfix config have below to settings:
	#   local_recipient_maps = proxy:unix:passwd.byname $alias_maps
	#   lias_maps = hash:/etc/aliases
	# It does two things, alias email and permit below email address to be received.
	tee /etc/aliases <<-EOF
	postmaster:    root
	dmarc:         root
	root:          admin@$DOMAIN
	EOF
	newaliases


	# https://www.postfix.org/virtual.5.html
	# By experiment find that a single "@example.com root@example.com" line in Postfix virtual alias will not cause loop.
	# postconf -e 'virtual_mailbox_maps = hash:/etc/postfix/vmailbox'
	postconf -e 'virtual_alias_maps = hash:/etc/postfix/virtual'
	tee /etc/postfix/virtual <<-EOF
	admin@$DOMAIN admin@$DOMAIN
	vaultwarden@$DOMAIN vaultwarden@$DOMAIN
	me@$DOMAIN me@$DOMAIN
	EOF
	postmap /etc/postfix/virtual
	# echo "@$DOMAIN root" >/etc/postfix/vmailbox
	# postmap /etc/postfix/vmailbox

	# The Filesystem Hierarchy Standard designated /var/mail to store mail. But this directory is used to stored mail
	#   in mbox format. I decided to use the made up directory /var/vmail to store mail for virtual user.
	# https://doc.dovecot.org/admin_manual/mailbox_formats/
	# https://wiki.dovecot.org/VirtualUsers/Home
	useradd -d /var/vmail -s /usr/sbin/nologin vmail
	mkdir /var/vmail
	chown vmail:vmail /var/vmail
	chmod 700 /var/vmail
	# sed -i '/^#auth_master_user_separator/c auth_master_user_separator = *' /etc/dovecot/conf.d/10-auth.conf

	# Disable the OS user 
	sed -i '/include auth-system.conf.ext/s/^/#/' /etc/dovecot/conf.d/10-auth.conf

	apt-get install -y apache2
	echo >/etc/dovecot/users
	htpasswd -B -i /etc/dovecot/users "admin@$DOMAIN" <<<'admin'
	htpasswd -B -i /etc/dovecot/users "vaultwarden@$DOMAIN" <<<'vaultwarden'
	htpasswd -B -i /etc/dovecot/users "me@$DOMAIN" <<<'me'

	# https://doc.dovecot.org/configuration_manual/authentication/passwd_file/
	# Regarding the CRYPT scheme, Dovecot uses libc’s crypt() function, which means that CRYPT is usually able to 
	#   recognize MD5-CRYPT and possibly also other password schemes.
	# https://doc.dovecot.org/configuration_manual/authentication/password_schemes/#other-supported-password-schemes
	# keywords: args
	tee /etc/dovecot/local.conf <<-EOF >/dev/null
	passdb {
	  driver = passwd-file
	  args = /etc/dovecot/users
	}

	userdb {
	  driver = static
	  args = uid=vmail gid=vmail home=/var/vmail/%d/%n
	}
	EOF

	# SPF
	# When a mail server receive an email, it will verify the FROM field of the email. It will query the MX record of the
	# domain of the FROM field, then check the A record of that MX record, and compare that A record with the IP address of
	# the SMTP server that send this email.
	#
	# postfix-policyd-spf-python is the popular method for Postfix to verify SPF.
	# It is listed at 'Hosted Software' on the open-spf website, http://www.open-spf.org/Software/
	# The software's main page is on https://launchpad.net/pypolicyd-spf/, the page state that these package is superseded
	# by SPF Engine. But the page on SPF engine state that it is to provides the back-end for both pypolicyd-spf and SPF milter.
	# This fact can be seen on Debian packages. postfix-policyd-spf-python is within source of spf-engine, 
	# and it depends on spf-engine. https://packages.debian.org/bullseye/postfix-policyd-spf-python
	# It has two manual pages.
	# https://manpages.debian.org/bullseye/postfix-policyd-spf-python/policyd-spf.1.en.html
	# https://manpages.debian.org/bullseye/postfix-policyd-spf-python/policyd-spf.conf.5.en.html
	# 
	# https://www.postfix.org/SMTPD_POLICY_README.html
	apt-get install -y postfix-policyd-spf-python
	tee -a /etc/postfix/master.cf <<-EOF >/dev/null
	policyd-spf unix - n n - 0 spawn
	  user=policyd-spf argv=/usr/bin/policyd-spf
	EOF
	# There is no need to put "reject_unauth_destination" on smtpd_recipient_restrictions because it is evaluate after
	#   smtpd_relay_restrictions. And smtpd_relay_restrictions already have defer_unauth_destination.
	# The difference of reject and defer is that defer is temporary error, the opposite side smtp server will retry latter.
	# It is a safe mechanism and valid default for smtp server.
	postconf -e 'smtpd_recipient_restrictions = check_policy_service unix:private/policyd-spf'
	postconf -e 'policyd-spf_time_limit = 3600s'

	# auto subscribe is necessary for Fairmail to recognize the folder function. 
	tee /etc/dovecot/conf.d/15-mailboxes.conf <<-EOF >/dev/null
	namespace inbox {
	mailbox Drafts {
	  auto = subscribe 
	  special_use = \Drafts
	}
	mailbox Junk {
	  auto = subscribe 
	  special_use = \Junk
	}
	mailbox Trash {
	  auto = subscribe 
	  special_use = \Trash
	}
	mailbox Archive {
	  auto = subscribe
	  special_use = \Archive 
	}
	mailbox Sent {
	  auto = subscribe 
	  special_use = \Sent
	}
	}
	EOF

	sed -i '/^mail_location =/c mail_location = maildir:~/Maildir' /etc/dovecot/conf.d/10-mail.conf
	sed -i "/^ssl_cert/c ssl_cert = </etc/letsencrypt/live/$hostname/fullchain.pem" /etc/dovecot/conf.d/10-ssl.conf
	sed -i "/^ssl_key/c ssl_key = </etc/letsencrypt/live/$hostname/privkey.pem" /etc/dovecot/conf.d/10-ssl.conf

	# Submission
	postconf -e 'smtpd_sasl_type = dovecot'
	postconf -e 'smtpd_sasl_path = private/auth'


	sed -f- -i /etc/dovecot/conf.d/10-master.conf <<-'EOF'
	/# Postfix smtp-auth/a \
	  unix_listener /var/spool/postfix/private/auth { \
	    mode = 0660 \
	    user = postfix \
	    group = postfix \
	  }
	EOF

	systemctl restart opendkim
	systemctl restart dovecot
	systemctl restart postfix
}
