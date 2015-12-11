#!/bin/sh

logger unix.sh
exec nc 10.3.1.2 666 </dev/null
