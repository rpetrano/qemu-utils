
QEMU_URI="${QEMU_URI:-"qemu:///system"}"
VIRSH="${VIRSH:-"virsh -c $QEMU_URI"}"

is_device_attached() {
	vm="$1"
	device="$2"

	vendorid=$(xmllint "$device" --xpath 'string(/hostdev/source/vendor/@id)')
	productid=$(xmllint "$device" --xpath 'string(/hostdev/source/product/@id)')

	xpath="count(/domain/devices/hostdev[@mode='subsystem' and @type='usb']/source/*[(self::vendor and @id='$vendorid') or (self::product and @id='$productid')])"

	$VIRSH dumpxml "$vm" | xmllint --xpath "$xpath" - | xargs test 2 -eq
}

# swap device between host and guest VM
swap_device() {
	vm="$1"
	device="$2"

	is_device_attached "$vm" "$device" &&
		$VIRSH detach-device "$vm" "$device" ||
		$VIRSH attach-device "$vm" "$device"
}

