#!/bin/bash

BD="$(dirname "$0")/../"
source "$BD/lib/common.sh"

swap_device win10 "$BD/devices/usbmouse.xml"
