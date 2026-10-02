#!/bin/sh
# Shiori for Linux in the Flatpak: the app is GJS modules (docs/linux.md).
exec gjs -m /app/share/shiori/linux/gjs/main.js "$@"
