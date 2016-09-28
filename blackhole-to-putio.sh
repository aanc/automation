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

	# Deleting torrent file
	rm -f $file

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
			zipResult=$(curl -XPOST --silent --data-urlencode "file_ids=$dlId" "https://api.put.io/v2/zips/create?oauth_token=${PUTIO_TOKEN}")

			zipStatus=$(jq -r '.status' <<< $zipResult)
			zipId=$(jq -r '.zip_id' <<< $zipResult)
			if [[ $zipStatus == OK ]]; then
				print_info "         -> Zip creation triggered, id $zipId"
				
				echo "ZIP_ID=$zipId" > ${dlId}.dlzip
				echo "DESTINATION_FOLDER=$BLACKHOLE" >> ${dlId}.dlzip
				echo "PUTIO_TOKEN=$PUTIO_TOKEN" >> ${dlId}.dlzip

				rm -f $BLACKHOLE/${dlId}.transfer
			else
				print_error "        -> Zip creation failed on put.io"
			fi
		else
			print_info "    - Triggering download job for $dlId"
			echo "URL=http://api.put.io/v2/files/${dlId}/download?oauth_token=${PUTIO_TOKEN}" > ${dlId}.dl
			echo "DESTINATION_FOLDER=$BLACKHOLE" >> ${dlId}.dl
			rm -f $BLACKHOLE/${dlId}.transfer
		fi
	done
else
	print_info "No watched transfer is finished, nothing to download"
fi
