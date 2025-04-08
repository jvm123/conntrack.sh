#!/bin/bash

## Installation script for conntrack.sh

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi
# Define source and destination paths
CONF_FILE="conntrack_sh.conf"
SCRIPT_FILE="conntrack.sh"
SCRIPT_FILE2="conntrack_ssh.sh"
CONF_DEST="/etc/$CONF_FILE"
SCRIPT_DEST="/usr/bin/$SCRIPT_FILE"
SCRIPT_DEST2="/usr/bin/$SCRIPT_FILE2"
DEPENDENCIES=(
    "conntrack"
    "netstat"
    "ssh"
)

# Confirm that dependencies are installed
for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        echo "Dependency $dep is not installed. Please install it and try again."
        exit 1
    fi
done

# Copy shell script to /usr/bin/
echo "Copying $SCRIPT_FILE to $SCRIPT_DEST..."
if cp "$SCRIPT_FILE" "$SCRIPT_DEST"; then
    chmod +x "$SCRIPT_DEST"
    echo "Shell script $SCRIPT_FILE installed successfully."
else
    echo "Failed to install shell script at $SCRIPT_DEST."
    exit 1
fi

# Copy 2md shell script to /usr/bin/
echo "Copying $SCRIPT_FILE2 to $SCRIPT_DEST..."
if cp "$SCRIPT_FILE2" "$SCRIPT_DEST2"; then
    chmod +x "$SCRIPT_DEST2"
    echo "Shell script $SCRIPT_FILE2 installed successfully."
else
    echo "Failed to install shell script at $SCRIPT_DEST2."
    exit 1
fi
# Copy configuration file to /etc/ with confirmation
if [ -f "$CONF_DEST" ]; then
    read -p -r "$CONF_DEST already exists. Overwrite? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Skipping configuration file installation."
        exit 0
    fi
fi

echo "Copying $CONF_FILE to $CONF_DEST..."
if cp "$CONF_FILE" "$CONF_DEST"; then
    echo "Configuration file installed successfully."
else
    echo "Failed to install configuration file at $CONF_DEST."
    exit 1
fi

echo "Installation completed."
