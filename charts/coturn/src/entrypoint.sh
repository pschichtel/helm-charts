#!/usr/bin/env sh

set -eu

config="/tmp/turnserver.conf"

# shellcheck disable=SC2005
echo "$(cat /config/base.conf)" > "$config"

for file in /static-users/*
do
    if [ -e "$file" ]
    then
        echo "user=$(basename "$file"):$(cat "$file")" >> "$config"
    fi
done

if [ -e /static-secret ]
then
    echo "static-auth-secret=$(cat "/static-secret")" >> "$config"
fi

# shellcheck disable=SC2005
echo "$(cat /config/extra.conf)" >> "$config"

exec turnserver -c "$config"