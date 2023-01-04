# Profile

# You can find the interface name by `ls /sys/class/net`
declare -A IFACE DISK1 DISK2 ARCH

IFACE[vbox]='enp0s3'
DISK1[vbox]='pci-0000:00:0f.0-scsi-0:0:1:0'
DISK2[vbox]='pci-0000:00:0f.0-scsi-0:0:2:0'
ARCH[vbox]='amd64'

IFACE[rpi]='eth0'
DISK1[rpi]='platform-fd500000.pcie-pci-0000:01:00.0-usb-0:1:1.0-scsi-0:0:0:0'
DISK2[rpi]='platform-fd500000.pcie-pci-0000:01:00.0-usb-0:2:1.0-scsi-0:0:0:0'
ARCH[rpi]='arm64'
