#!/bin/bash

source common.sh

[[ -z $BLACKHOLE ]] && print_error "BLACKHOLE is not set" && exit 1
[[ -z $PUTIO_TOKEN ]] && print_error "PUTIO_TOKEN is not set" && exit 1

transfersToDelete=""
for t in $(ls ${BLACKHOLE}/*.{downloaded,zipped} 2>/dev/null); do
	id=$(cut -d'.' -f1 <<< $(basename "$t"))
	state=$(curl --silent "https://api.put.io/v2/transfers/${id}?oauth_token=${PUTIO_TOKEN}" | jq -r .transfer.status 2>/dev/null)
	if [[ $state == COMPLETED ]]; then
		print_info "$id can be deleted"
		[[ -n $transfersToDelete ]] && comma=","
		transfersToDelete+=$comma$id
	else
		if [[ -n $state ]]; then
			print_info "$id is $state, skipping"
		else
			print_warn "$id does not exist in transfer list, cleaning locally"
			rm -f $t
		fi
	fi
done

if [[ -n $transfersToDelete ]]; then
	print_info "Deleting transfers ${transfersToDelete} ..."
	result=$(curl -XPOST --silent --data-urlencode "transfer_ids=${transfersToDelete}" "https://api.put.io/v2/transfers/cancel?oauth_token=${PUTIO_TOKEN}")
	response=$(jq -r .status 2>/dev/null <<< $result)
	if [[ $response == OK ]]; then
		rm -f ${BLACKHOLE}/{$transfersToDelete}.{downloaded,zipped}
		print_success "Cleanup done"
	else 
		print_error "Something went wrong during cleanup"
		exit 1
	fi
else
	print_success "Already clean, nothing to do."
fi
exit 0
