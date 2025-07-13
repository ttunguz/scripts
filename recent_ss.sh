#!/bin/bash

# Find the most recent file in the screenshots directory
LATEST_SCREENSHOT=$(ls -t ~/Documents/screenshots/ | head -n 1)

# Construct the full path to the screenshot
FULL_PATH="$HOME/Documents/screenshots/${LATEST_SCREENSHOT}"

# Upload the file using cloud.sh
~/Documents/coding/scripts/cloud.sh "${FULL_PATH}"
