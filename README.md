# Selfhood
Security-focused personal cloud for suspicious self-hosters. An all-round solution that takes into account data integrity, VPN, backup and restore.

# Introduction
Like other self-hosting built, it bundled a bunch of applications in it.

## Included server-side apps
* ownCloud
* Collabora Online (CODE)
* Syncthing
* Vaultwarden
* DNSCrypt Proxy
## Server Architecture
![Server Architecture](assets/architecture.svg)

## The special features of this built
* **Use ZFS** No need to explain.
* **Easy to try and deploy** Environment variable preset for VirtualBox and Raspberry Pi 4/400 is provided to make it easy to try and deploy
* **Minimum Root CA Trust** The server will only opt-in needed root CA to minimize the attack surface. Currently, only GlobalSign, Amazon, ISRG and DigiCert are trusted.
* **Hourly Zero Downtime Backup** The server utilize ZFS snapshot, restic and rclone to achieve hourly zero downtime backup.
* **Easy Restoration** The same installation script can handle data restoration on reinstall, upgrade and migrate, the target server just need to attach the original hard drives, or connect to the original restic repository.
* **Use your self-hosted VPN and other VPN service together** The server will connect to your subscriped VPN provider and your client devices will connect to the server. So that you can access your self-hosted services securely, and browse the Internet securely together.
* **Multiple WireGuard Profile** The server can be configured multiple WireGuard connections to your subscriped VPN provider, and the installation script will generate the configuration files for all of your client devices. So that the user can connect to VPN server in different country by simply switching profile on the official WireGuard client.
* **Very Private** The traffic between your client and server is end-to-end encrypted by WireGuard, no matter you are using Wi-Fi or cellular network. And you will exchange the credential offline, so you don't even need to trust any root CA, the HTTPS certificate is just for decoration. The firewall rules are carefully crafted to prevent un-tunnelled client's traffic leaking to physical network, and constrain the self-hosted services can only be accessed via VPN.
* **DNS and Ad-blocking** The WireGuard configuration file will make the client device to use the self-hosted DNS server, which use DNSCrypt to prevent DNS spoofing. It also have domain name filtering function to block ads, using the oisd blocklist.
* **Enhanced Configuration** Some changes are made on the default configuration of the OS and software to eliminate warnings, optimize performance and increase security.
* **DeGoogle** The bundled server-side apps can replace most cloud sync needs.

||Server|Android client|Windows client|
| ----- | ------------- |-------------| -----|
|Calendar|ownCloud|DAVx⁵|ownCloud Calendar web app| 
|Contacts|ownCloud|DAVx⁵|ownCloud Contacts web app|
|Notes|ownCloud|Joplin|Joplin|
|Password Manager|Vaultwarden|Bitwarden|Bitwarden|
|Cloud Drive|ownCloud|ownCloud|ownCloud (support VFS)|
|Gallery|Syncthing|Syncthing + built-in gallery app|Syncthing + Windows Photos|
|Office|Collabora CODE|ownCloud + Collabora Office|ownCloud Collabora Online web app|


# Installation
The installation method is to run the installation script on a fresh Debian system (support amd64 platform and Raspberry Pi 4/400).

# Preparation
1.  **env.sh**. Rename **env.example.sh** to **env.sh**, customize it with your configuration. You would need to review all variables in **Basic configuration**. The default value of **Advanced configuration** should work.
2.   **rclone.conf**. Have to prepare the RCLONE credential in advance because the server will not have desktop environment. Put this file under the credentials directory,  `credentials/rclone.conf`.
3.	**The WireGuard configuration files**. Put all the WireGuard configuration files of your subscriped VPN service under the `credentials/wg_config_files` directory, like `credentials/wg_config_files/1-JP_75.conf` , `credentials/wg_config_files/5-CH_15.conf`. The only required fields are PrivateKey, Address, PublicKey and Endpoint.
4.	**Hardware** A server with two drives dedicate to the data, it means 3 drives in total including the OS drive.

# Installation
## General installation procedure
1. Edit your configuration in **env.sh**
2. Copy **rclone.conf** to the credentials directory
3. Copy the **WireGuard configuration files** to the credentials/wg_config_files directory
4. Log into the fresh Debian system as root.
5. Run `./system.sh`, the system will restart when finished. 
6. After system restarted, run `./user.sh`. There are three path:
	- New Installation
		1.  You will see **Installation complete** at the end when the installation is finished.
		2.  Get the WireGuard configurations for your user device from **/root/wireguard-configs**
		3. Connect to the server through WireGuard from your user device.
		4.  Play around the services, change all administrative passwords.
		5.  If everything is normal, run `production-cert.sh` to replace the test cert with a production cert.
		6.  run `restic init` to initialize the restic repository.
		7.  Run `backup-full`, then use `restic snapshots` to verify it.
	- Restore from disk
		1.  You will see **Installation complete** at the end when the installation is finished. Everything should work as before
	- Restore from restic
		1. There is one more question 1 minutes after the installation started, to ask which snapshot you want to restore.
		2. You will see **Installation complete** at the end when the installation is finished. Everything should work as before
7.  Uncomment the `backup-full` line at **/etc/cron.d/backup** to enable hourly restic backup.

## Raspberry Pi 4 / 400 installation procedure
1. Copy the content of this project to a USB drive.
2. Edit your configuration in **env.sh**
3. Copy **rclone.conf** to the credentials directory
4. Copy the **WireGuard configuration files** to the credentials/wg_config_files directory
5. Flash Debian to the SD card.
6. At the Raspberry Pi, insert the SD card, attach the USB drive to the USB2.0 port and insert two SSD to the USB3.0 port. 
7. Boot and login as root with empty password.
8.  Create a mount point for the USB drive and mount it, `mkdir /mnt/usb1`, `mount /dev/sdc1 /mnt/usb1`
9. Then, follow step 5 of **General installation procedure** to the end.

## VirtualBox installation procedure
1. Create a Debian VM, select Attached to **Bridged Adatper** on the Network tab, select **virtio-scsi** controller on Storage tab, attach **two more hard disk** to this controller.
2. Clean install Debian. During installation, only select **Standard System Utilities** on Software selection. 
3. Login as root,  un-comment the CD line in /etc/apt/sources.list
4. `apt-get update`, `apt-get upgrade`
5. `apt-get install build-essential linux-headers-amd64 openssh-server`
6. Insert Guest Additions CD Image, then execute the following command to install it.
	```
	mkdir /mnt/guest
	mount -o ro /dev/cdrom /mnt/guest
	cd /mnt/guest
	sh VBoxLinuxAdditions.run
	reboot
	```
7. Then, follow step 5 of **General installation procedure** to the end.



# Usage
## Services URI
### ownCloud
URL: owncloud.yourdomain.com
username: admin
password: admin

### Syncthing GUI
URL: syncthing.yourdomain.com
username: admin
password: admin

### Vaultwarden admin
URL: vaultwarden.tsewaiho.me/admin
admin token: admin

# WireGurd Kill Switch on user device
Go Windows Security > Firewall & network protection > Advanced settings > Windows Defender Firewall Properties > Public Profile, change the value of Outbound connections to **Block**.
Run `REG ADD HKLM\SOFTWARE\WireGuard /v DangerousScriptExecution /t REG_DWORD /d 1 /f` on cmd or powershell.
The Windows firewall have rule to allow outbound DNS traffic, but you cannot use the Windows DoH DNS.