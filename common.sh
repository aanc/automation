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

# External notification tools
send_slack_notification() {
	local msg="$1"

	slackJson="{}"
	[[ -n $SLACK_CHANNEL ]] && slackJson=$(jq '{"channel": "'$SLACK_CHANNEL'"}' <<< $slackJson)
	[[ -n $SLACK_USERNAME ]] && slackJson=$(jq '. + {"username": "'$SLACK_USERNAME'"}' <<< $slackJson)
	[[ -n $SLACK_ICON_URL ]] && slackJson=$(jq '. + {"icon_url": "'"$SLACK_ICON_URL"'"}' <<< $slackJson)
	slackJson=$(jq '. + {"text": "'"$msg"'"}' <<< $slackJson)

	notifResult=$(curl --silent -X POST --data-urlencode "payload=$slackJson" $SLACK_WEBHOOK_URL)
	[[ $notifResult != ok ]] && print_error "Something went wront when sending Slack notification"

}
