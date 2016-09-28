#!/bin/bash

# Colors
RED="\\033[1;31m"
GREEN="\\033[1;32m"
YELLOW="\\033[1;33m"
BLUE="\\033[1;34m"
MAGENTA="\\033[1;35m"
CYAN="\\033[1;36m"
BOLD="\033[1m"
END="\\033[1;00m"
FATAL="\\033[1;37;41m" # White on red

# Printing stuff
print_info() {
	local msg=$1
	echo -e "${BLUE} [INFO]${END} $msg"
	return 0
}

print_error() {
	local msg=$1
	echo -e "${RED}[ERROR] $msg${END}"
	return 0
}

print_success() {
	local msg=$1
	echo -e "${GREEN}   [OK] $msg${END}"
	return 0
}
