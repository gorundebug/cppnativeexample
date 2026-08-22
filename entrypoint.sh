#!/bin/sh
set -eu

service="$1"
case "$service" in
  inventory) binary="inventoryservice" ;;
  orders) binary="orderservice" ;;
  *) echo "unknown service: $service" >&2; exit 2 ;;
esac
workers="${NATIVE_WORKER_THREADS:-2}"
connections="${INVENTORY_SERVICE_API_CONNECTIONS_COUNT:-1}"
template="/app/config/${service}.static_config.yaml"
config="/tmp/${service}.static_config.yaml"
sed -e "s/@WORKERS@/${workers}/g" -e "s/@CONNECTIONS@/${connections}/g" "$template" > "$config"
exec "/usr/local/bin/${binary}" --config "$config"
