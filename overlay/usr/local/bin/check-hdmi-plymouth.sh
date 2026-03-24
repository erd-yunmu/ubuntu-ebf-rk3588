#!/bin/bash

HDMI1=$(cat /sys/class/drm/card0-HDMI-A-1/status 2>/dev/null)
HDMI2=$(cat /sys/class/drm/card0-HDMI-A-2/status 2>/dev/null)
DP=$(cat /sys/class/drm/card0-DP-1/status 2>/dev/null)

if [[ "$HDMI1" == "connected" ]] || [[ "$HDMI2" == "connected" ]] || [[ "$DP" == "connected" ]]; then
    exit 0
else
    /usr/bin/plymouth quit 2>/dev/null || true
    exit 0
fi
