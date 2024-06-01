#!/usr/bin/env sh

set -eu

config="/tmp/turnserver.conf"

echo "listening-ip=${POD_IP:-"0.0.0.0"}" > "$config"

# shellcheck disable=SC2005
echo "$(cat /config/base.conf)" >> "$config"


if [ -e /static-secret ]
then
    echo "static-auth-secret=$(cat "/static-secret")" >> "$config"
else
    for file in /static-users/*
    do
        if [ -e "$file" ]
        then
            echo "user=$(basename "$file"):$(cat "$file")" >> "$config"
        fi
    done
fi

# shellcheck disable=SC2005
echo "$(cat /config/extra.conf)" >> "$config"

exec turnserver -c "$config"