#!/bin/bash

set -eu -o pipefail

BASE=$(dirname $(readlink -f $0))
source $BASE/profiles.sh
source $BASE/env.sh
source $BASE/lib/helpers.sh

runasroot

# Common OS setup
source $BASE/components/common.sh

# Enable Trim on Crucial X6 1TB Portable SSD
# https://wiki.archlinux.org/title/Solid_state_drive#External_SSD_with_TRIM_support
echo 'ACTION=="add|change", ATTRS{idVendor}=="0634", ATTRS{idProduct}=="5602", SUBSYSTEM=="scsi_disk", ATTR{provisioning_mode}="unmap"' >/etc/udev/rules.d/10-uas-discard.rules
# Tests:
# blkdiscrd <path of the Crucial X6 1TB Portable SSD>
# It works if it do not return error because blkdiscard can only run on device that support TRIM.
#
# There is an issue which is sometimes TRIM enabling will be failed, and the system prompt error 
#   message "sdb1: Error: discard_granularity is 0.".
# This bug is addressed is hopefully will be patch in the future kernel.
# https://lore.kernel.org/all/20220626035913.99519-1-me@manueljacob.de/#r

echo "system.sh finished. System will restart in 10 seconds."
sleep 10

reboot
