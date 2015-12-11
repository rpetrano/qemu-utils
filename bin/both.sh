#!/bin/bash

BD="$(dirname "$0")/../"
source "$BD/lib/common.sh"

vm=win10
keyboard="$BD/devices/usbkeyboard.xml"
mouse="$BD/devices/usbmouse.xml"

# Keyboard is the referent device
is_device_attached "$vm" "$keyboard" &&
	action=detach ||
	action=attach

$VIRSH $action-device "$vm" "$keyboard"
$VIRSH $action-device "$vm" "$mouse"
