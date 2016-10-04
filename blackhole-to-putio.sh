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

print_info "Retrieving completed transfers list ..."
completedTransfersList=$(curl --silent "https://api.put.io/v2/transfers/list?oauth_token=${PUTIO_TOKEN}")

declare -a retrieveList
oIFS=$IFS
IFS=$'\n'
for line in $(jq -r '.transfers[] | select(.status == "SEEDING" or .status == "COMPLETED")  | (.id | tostring) + ":" + .name + ":" + (.file_id | tostring)' <<< $completedTransfersList)
do
	dlId=$(cut -d':' -f1 <<< $line)
	dlName=$(cut -d':' -f2 <<< $line)
	fileId=$(cut -d':' -f3 <<< $line)

	if [[ -f  $BLACKHOLE/${dlId}.transfer ]]; then
		print_info "    - ${BOLD}$dlId${END} : ${GREEN}$dlName${END}"

		# Get file type (folder or file)
		dlType=$(curl --silent "https://api.put.io/v2/files/${fileId}?oauth_token=${PUTIO_TOKEN}" | jq -r .file.file_type)

		# Building triggers files for jenkins jobs
		if [[ $dlType == FOLDER ]]; then
			print_info "        -> $dlId is a folder, zip needed"
			zipResult=$(curl -XPOST --silent --data-urlencode "file_ids=$fileId" "https://api.put.io/v2/zips/create?oauth_token=${PUTIO_TOKEN}")

			zipStatus=$(jq -r '.status' <<< $zipResult)
			zipId=$(jq -r '.zip_id' <<< $zipResult)
			if [[ $zipStatus == OK ]]; then
				print_info "        -> Zip creation triggered, id $zipId"
				
				echo "ZIP_ID=$zipId" > ${dlId}.dlzip
				echo "DESTINATION_FOLDER=$BLACKHOLE" >> ${dlId}.dlzip
				echo "PUTIO_TOKEN=$PUTIO_TOKEN" >> ${dlId}.dlzip

				mv $BLACKHOLE/${dlId}.transfer $BLACKHOLE/${dlId}.zipped
			else
				print_error "        -> Zip creation failed on put.io"
			fi
		else
			print_info "    - Triggering download job for $dlId"
			echo "URL=http://api.put.io/v2/files/${fileId}/download?oauth_token=${PUTIO_TOKEN}" > ${dlId}.dl
			echo "DESTINATION_FOLDER=$BLACKHOLE" >> ${dlId}.dl
			mv $BLACKHOLE/${dlId}.transfer $BLACKHOLE/${dlId}.downloaded
		fi
	else
		print_info "    - ${BOLD}$dlId${END} : ${YELLOW}$dlName${END}"
	fi

done
IFS=$oIFS

