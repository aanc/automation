#!/bin/bash

source common.sh

[[ -z $BLACKHOLE ]] && print_error "BLACKHOLE is not set" && exit 1
[[ -z $PUTIO_TOKEN ]] && print_error "PUTIO_TOKEN is not set" && exit 1
[[ -z $PROCESSED_FOLDER ]] && print_error "PROCESSED_FOLDER is not set" && exit 1
[[ -z $DOWNLOADED_FOLDER ]] && print_error "DOWNLOADED_FOLDER is not set" && exit 1
[[ -z $DL_JOB_NAME= ]] && print_error "DL_JOB_NAME is not set" && exit 1
[[ -z $DL_JOB_TOKEN= ]] && print_error "DL_JOB_TOKEN is not set" && exit 1


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

	# Looking for transfer torrent
	torrent=$(find $PROCESSED_FOLDER -name "*.${dlId}.processed")

	if [[ -n $torrent ]]; then
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
				print_info "        -> This job does not handle zip file atm. Skipping".
				continue

				print_info "        -> Zip creation triggered, id $zipId"
				
				echo "ZIP_ID=$zipId" > ${dlId}.dlzip
				echo "DESTINATION_FOLDER=$BLACKHOLE" >> ${dlId}.dlzip
				echo "PUTIO_TOKEN=$PUTIO_TOKEN" >> ${dlId}.dlzip

			else
				print_error "        -> Zip creation failed on put.io"
			fi
		else
			URL="http://api.put.io/v2/files/${fileId}/download?oauth_token=${PUTIO_TOKEN}"
			print_info "        -> Triggering download job for $dlId ($URL)"
			curl -L "${JENKINS_URL}/job/${DL_JOB_NAME}/buildWithParameters?token=${DL_JOB_TOKEN}&ZIP=false&FILE_URL=${URL}" -u trigger:ttrriiggeerr
			mv $torrent $DOWNLOADED_FOLDER/$(basename $torrent).$(date +"%Y-%m-%d_%H-%M").downloaded
		fi
	else
		print_info "    - ${BOLD}$dlId${END} : ${YELLOW}$dlName${END}"
		print_info "        -> Transfer not managed by Sickrage/Jenkins or already downloaded"
	fi

done
IFS=$oIFS

