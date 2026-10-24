#!/bin/bash

for governor in /sys/devices/platform/*.gpu*/devfreq/*/governor; do
    [ -w "${governor}" ] || continue
    echo performance > "${governor}" 2> /dev/null || true
done
