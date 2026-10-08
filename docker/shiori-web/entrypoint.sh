#!/bin/sh
# Starts shiori-web: configure.py checks the settings (and stops with a plain message if they're wrong), stamps them
# into a copy of the pages and writes nginx's config, all under /tmp; then nginx runs in the foreground.
set -eu
mkdir -p /tmp/nginx /tmp/shiori
python3 /opt/shiori/configure.py
exec nginx -c /opt/shiori/nginx.conf -g 'daemon off;'
