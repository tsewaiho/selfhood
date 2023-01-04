# Cloudflare
#
# Environment variables
#  - MASTER_PASSWORD
#  - RESTIC_REPOSITORY
#
# Resources
#  - rclone.conf

apt-get install -y libarchive-tools wget bzip2 argon2

# Restic
# sha256sum -c restic_0.12.1_linux_arm.bz2.sha256
# bzip2 -dkc restic_0.12.1_linux_arm.bz2 > /usr/bin/restic
declare -A restic_download_link
restic_download_link[amd64]=https://github.com/restic/restic/releases/download/v0.14.0/restic_0.14.0_linux_amd64.bz2
restic_download_link[arm64]=https://github.com/restic/restic/releases/download/v0.14.0/restic_0.14.0_linux_arm64.bz2
wget -O- ${restic_download_link[${ARCH[$PROFILE]}]} | bzip2 -dc >/usr/bin/restic
chmod 755 /usr/bin/restic
mkdir -p $HOME/.config/restic
# echo $MASTER_PASSWORD >$HOME/.config/restic/restic-password
z85_hash 'selfhood-restic-backup' >$HOME/.config/restic/restic-password
echo $RESTIC_REPOSITORY >$HOME/.config/restic/restic-repository
chmod -R u=rX,g=,o= $HOME/.config/restic
echo 'export RESTIC_REPOSITORY_FILE=$HOME/.config/restic/restic-repository' >>$HOME/.bashrc
echo 'export RESTIC_PASSWORD_FILE=$HOME/.config/restic/restic-password' >>$HOME/.bashrc
export RESTIC_REPOSITORY_FILE=$HOME/.config/restic/restic-repository
export RESTIC_PASSWORD_FILE=$HOME/.config/restic/restic-password

# Rclone
# Needs to pre-configure on Windows first, copy the rclone.conf from %APPDATA%\rclone
# libarchive-tools for bsdtar
declare -A rclone_download_link
rclone_download_link[amd64]=https://downloads.rclone.org/rclone-current-linux-amd64.zip
rclone_download_link[arm64]=https://downloads.rclone.org/rclone-current-linux-arm64.zip
wget -O- ${rclone_download_link[${ARCH[$PROFILE]}]} | bsdtar -xf - --strip-components=1 -C /usr/bin rclone-*-linux-*/rclone
chmod 755 /usr/bin/rclone
mkdir -p $HOME/.config/rclone
cp $BASE/credentials/rclone.conf $HOME/.config/rclone/
chmod 600 $HOME/.config/rclone/rclone.conf
