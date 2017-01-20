#!/bin/bash

source common.sh

[[ -z $BLACKHOLE ]] && print_error "BLACKHOLE is not set" && exit 1
[[ -z $PROCESSED_FOLDER ]] && print_error "PROCESSED_FOLDER is not set" && exit 1
[[ -z $PUTIO_TOKEN ]] && print_error "PUTIO_TOKEN is not set" && exit 1
[[ -z $FOLDER_ID ]] && print_error "FOLDER_ID is not set" && exit 1

for file in $(find $BLACKHOLE -name "*.torrent")
do
	print_info "Processing ${BOLD}$(basename $file)${END}"

	result=$(curl --silent -F file=@${file} \
		"https://upload.put.io/v2/files/upload?oauth_token=${PUTIO_TOKEN}&parent_id=${FOLDER_ID}" \
	)

	status=$(jq -r .status <<< $result)
	if [[ $status == ERROR ]]; then
		error_message=$(jq -r .error_message <<< $result)
		print_error "$error_message"
		echo
		continue
	fi

	id=$(jq -r .transfer.id <<< $result)
	print_success "Transfer added with id $id"

	# moving torrent to processed folder
	mv $file $PROCESSED_FOLDER/$(basename ${file}).$(date +"%Y-%m-%d_%H-%M").${id}.processed

	if [[ -n $SLACK_WEBHOOK_URL ]]; then
		print_info "Sending notification to Slack"
		send_slack_notification "Torrent $(basename ${file}) sent to Put.io"
	fi
	echo

done


