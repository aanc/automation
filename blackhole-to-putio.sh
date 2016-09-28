#!/bin/bash

source common.sh

[[ -z $BLACKHOLE ]] && print_error "BLACKHOLE is not set" && exit 1
[[ -z $PUTIO_TOKEN ]] && print_error "PUTIO_TOKEN is not set" && exit 1
[[ -z $FOLDER_ID ]] && print_error "FOLDER_ID is not set" && exit 1

for file in $(find $BLACKHOLE -name "*.torrent")
do
	print_info "Processing ${BOLD}$(basename $file)${END}"

	result=$(curl --silent -F file=@${file} \
		"https://upload.put.io/v2/files/upload?oauth_token=${PUTIO_TOKEN}&parent_id=${FOLDER_ID}" \
	)
#	jq . <<< $result

	status=$(jq -r .status <<< $result)
	if [[ $status == ERROR ]]; then
		error_message=$(jq -r .error_message <<< $result)
		print_error "$error_message"
		echo
		continue
	fi

	id=$(jq -r .transfer.id <<< $result)
	print_success "Transfer added with id $id"

	# Creating file for transfer tracking
	touch $BLACKHOLE/${id}.transfer

	# Marking torrent as processed
	mv $file ${file}.$(date +"%Y-%m-%d_%H-%M").processed

	if [[ -n $SLACK_WEBHOOK_URL ]]; then
		print_info "Sending notification to Slack"
		send_slack_notification "Torrent $(basename ${file}) sent to Put.io"
	fi
	echo

done

print_info "Retrieving completed downloads list ..."
completedDownloadsJson=$(curl --silent "https://api.put.io/v2/files/list?oauth_token=${PUTIO_TOKEN}&parent_id=${FOLDER_ID}")

declare -a retrieveList
oIFS=$IFS
IFS=$'\n'
for line in $( jq -r '.files[] | (.id | tostring) + ":" + .name + ":" + .file_type' <<< $completedDownloadsJson)
do
	dlId=$(cut -d':' -f1 <<< $line)
	dlName=$(cut -d':' -f2 <<< $line)
	dlType=$(cut -d':' -f3 <<< $line)

	# Checking if file is one we need
	weNeedThisFile=0
	[[ -f $BLACKHOLE/${dlId}.transfer ]] && weNeedThisFile=1

	[[ $weNeedThisFile == 1 ]] && retrieveList+=("$dlId:$dlType")

	color=$YELLOW
	[[ $weNeedThisFile == 1 ]] && color=$GREEN 
	print_info "    - ${BOLD}$dlId${END} : ${color}$dlName${END}"
done
IFS=$oIFS

echo
if [[ -n ${retrieveList[0]} ]]; then
	print_info "Downloading watched transfers ..."

	for file in ${retrieveList[@]}
	do
		dlId=$(cut -d':' -f1 <<< $file)
		dlType=$(cut -d':' -f2 <<< $file)

		if [[ $dlType == FOLDER ]]; then
			print_info "    - $dlId is a folder, zip needed"
		else
			print_info "    - Downloading $dlId"
			pushd $BLACKHOLE &>/dev/null
			mv $BLACKHOLE/${dlId}.transfer  $BLACKHOLE/${dlId}.downloading
			aria2c -x 12 "http://api.put.io/v2/files/${dlId}/download?oauth_token=${PUTIO_TOKEN}"
			mv  $BLACKHOLE/${dlId}.downloading  $BLACKHOLE/${dlId}.downloaded
			popd &>/dev/null
		fi
	done
else
	print_info "No watched transfer is finished, nothing to download"
fi
