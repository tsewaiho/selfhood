# Docker

apt-get install -y wget gpg
wget -O- https://download.docker.com/linux/debian/gpg | gpg --dearmor >/usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] http://download.docker.com/linux/debian $(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce