#!/bin/bash

source common.sh

[[ -z $BLACKHOLE ]] && print_error "BLACKHOLE is not set" && exit 1
[[ -z $PUTIO_TOKEN ]] && print_error "PUTIO_TOKEN is not set" && exit 1
[[ -z $PROCESSED_FOLDER ]] && print_error "PROCESSED_FOLDER is not set" && exit 1
[[ -z $DOWNLOADED_FOLDER ]] && print_error "DOWNLOADED_FOLDER is not set" && exit 1
[[ -z $DL_JOB_NAME= ]] && print_error "DL_JOB_NAME is not set" && exit 1
[[ -z $DL_JOB_TOKEN= ]] && print_error "DL_JOB_TOKEN is not set" && exit 1
[[ -z $JENKINS_PASSWORD ]] && print_error "JENKINS_PASSWORD is not set" && exit 1
[[ -z $JENKINS_USER ]] && print_error "JENKINS_USER is not set" && exit 1

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

		if [[ $dlType == FOLDER ]]; then
			print_info "        -> $dlId is a folder, zip needed"
			zipResult=$(curl -XPOST --silent --data-urlencode "file_ids=$fileId" "https://api.put.io/v2/zips/create?oauth_token=${PUTIO_TOKEN}")

			zipStatus=$(jq -r '.status' <<< $zipResult)
			zipId=$(jq -r '.zip_id' <<< $zipResult)

			if [[ $zipStatus == OK ]]; then
				print_info "        -> Zip creation triggered, id $zipId"
				
				zip=true	
				url=
				while [[ -z $url || $url == false ]]; do
					url="$(curl -XGET --silent "https://api.put.io/v2/zips/${zipId}?oauth_token=${PUTIO_TOKEN}" | jq -r ".url")"
					print_info "        -> Waiting for zip creation on put.io ..."
					sleep 10
				done

				print_info "        -> Zip creation complete, url is $url"

			else
				print_error "        -> Zip creation failed on put.io"
				continue
			fi
		else
			url="http://api.put.io/v2/files/${fileId}/download?oauth_token=${PUTIO_TOKEN}"
			zip=false
		fi
		
		print_info "        -> Triggering download job from $url"
		url=$(sed -e "s/&/%26/g" <<< $url)
		curlStatus=$(curl -k -L -w "%{http_code}" "${JENKINS_URL}/job/${DL_JOB_NAME}/buildWithParameters?token=${DL_JOB_TOKEN}&ZIP=${zip}&FILE_URL=${url}" -u ${JENKINS_USER}:${JENKINS_PASSWORD})

		if [[ $curlStatus == 201 ]]; then
			mv $torrent $DOWNLOADED_FOLDER/$(basename $torrent).$(date +"%Y-%m-%d_%H-%M").downloaded
		else
			print_error "        -> Something went wrong during job triggering (HTTP $curlStatus)"
		fi
	else
		print_info "    - ${BOLD}$dlId${END} : ${YELLOW}$dlName${END}"
		print_info "        -> Transfer not managed by Sickrage/Jenkins or already downloaded"
	fi

done
IFS=$oIFS

