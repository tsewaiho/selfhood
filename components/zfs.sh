# ZFS

zfs_install () {
	apt-get install -y linux-headers-$(uname -r) rsync
	debconf-set-selections <<< "zfs-dkms zfs-dkms/note-incompatible-licenses note true"
	apt-get install -t bullseye-backports --no-install-recommends -y zfs-dkms
	apt-get install -t bullseye-backports -y zfsutils-linux

	# The Debian zfs package will install its zfs CRON for trim and scrub, delete it if you want to customize the behavior.
	# The original author said the update won't add it back
	# https://bugs.launchpad.net/ubuntu/+source/zfs-linux/+bug/1860228/comments/4
	rm /etc/cron.d/zfsutils-linux
}

zfs_create_zpool () {
	wipefs -a "/dev/disk/by-path/${DISK1[$PROFILE]}" "/dev/disk/by-path/${DISK2[$PROFILE]}"
	zpool create -o ashift=12 -O compression=zstd tank mirror ${DISK1[$PROFILE]} ${DISK2[$PROFILE]}
}

zfs_import_zpool () {
	local zpool_opt_f=''
	until zpool import $zpool_opt_f -d /dev/disk/by-path tank; do
		echo 'zpool import failed.'
		select choice in 'retry' 'force-retry' 'exit'; do
			case $choice in
				retry )
					echo "Retry..."
					zpool_opt_f=''
					break
					;;
				force-retry )
					echo "Retry (force)..."
					zpool_opt_f='-f'
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

zfs_create_filesystem_with_data () {
	local name=$1 mountpoint=$2
	if ! zfs list $name; then
		mv $mountpoint "$mountpoint.tmp"
		zfs create -o mountpoint=$mountpoint $name
		rsync -a "$mountpoint.tmp/" $mountpoint
		rm -rf "$mountpoint.tmp"
	fi
}

zfs_cron () {
	tee /etc/cron.d/zfs <<-EOF >/dev/null
	PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	0 5 * * 0 root zpool scrub tank
	0 5 * * 1-6 root zpool trim tank
	EOF
}
