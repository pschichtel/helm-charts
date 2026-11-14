#!/bin/bash
# nginx frontend for unifi-core (UI on 80/8443, supervisor on 11084).
# unifi-core generates the dynamic site configs + cert in
# /data/unifi-core/config/http at boot; wait until the config is valid.
set -e

# same preamble the pre-start hook does in the unifi-core container
cp -f /etc/nginx/nginx.conf.disabled /etc/nginx/nginx.conf

for i in $(seq 1 180); do
  nginx -t >/dev/null 2>&1 && break
  sleep 2
done
nginx -t
exec nginx -g 'daemon off;'
