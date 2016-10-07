#!/bin/bash

source common.sh

[[ -z $INFLUXDB ]] && print_error "INFLUXDB variable should be set with influxdb ip and port (ip:port)" && exit 1

[[ -f data.idb ]] && rm -f data.idb

# Export data from livebox
print_info "Exporting data from livebox ..."
curl --connect-timeout 10 -s -H "Content-type: application/json" -d '{"parameters":{}}' "http://192.168.1.1/sysbus/Devices:get" | jq -r '.result.status[] | select((.Tags | contains("self")) != true) | select((.Tags | contains("logical")) != true) | select(.DeviceType != "Phone") | select((.Tags | contains("phone")) != true) | "devices,mac=" + .Key + " value=" + (.Active|tostring|sub("true"; "1")|sub("false";"0"))'  > data.idb
cat data.idb

# Send data to influxdb
print_info "Sending data to influxdb at $INFLUXDB"

curl -i -XPOST "http://${INFLUXDB}/write?db=livebox" --data-binary "@data.idb"
