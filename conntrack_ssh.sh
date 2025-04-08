#!/bin/bash
# Function to determine notification icon based on log content
get_notification_icon() {
    local line="$1"
    
    # Default icon
    local icon="dialog-information"
    
    # Check for critical or warning conditions
    if [[ "$line" == *"!! "* ]]; then
        icon="dialog-error"
    elif [[ "$line" == *"! "* ]]; then
        icon="dialog-warning"
    fi
    
    echo "$icon"
}

# Function to display usage information
usage() {
    echo "Usage:"
    echo "  $0 -h, --help"
    echo "  $0 --install user@hostname"
    echo "  $0 --run user@hostname [logfile]"
    echo "  $0 --watch user@hostname [logfile]"
    echo "Default logfile: /var/log/conntrack_sh.log"
    exit 1
}

# Parse arguments
ACTION="$1"
if [ $# -lt 2 ] || [[ "$ACTION" != "--install" && "$ACTION" != "--run" && "$ACTION" != "--watch" ]]; then
    usage
fi
REMOTE_HOST="$2"
LOGFILE="${3:-/var/log/conntrack_sh.log}"
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Broadcast notifications to all terminals
BROADCAST=false

# Define source and destination paths
CONF_FILE="conntrack_sh.conf"
SCRIPT_FILE="conntrack.sh"
CONF_DEST="/etc/$CONF_FILE"
SCRIPT_DEST="/usr/bin/$SCRIPT_FILE"

## Load config file
CONFIG_FILE="/etc/conntrack_sh.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

case "$ACTION" in
    --install)
        echo "Installing conntrack.sh and configuration on $REMOTE_HOST..."

        # Copy the script and configuration file to the remote host
        scp "$SCRIPT_DIR/conntrack_ssh.sh" "$REMOTE_HOST:$SCRIPT_DEST" || { echo "Failed to copy script to $REMOTE_HOST. Ensure you have the correct permissions."; exit 1; }
        scp /etc/conntrack_sh.conf "$REMOTE_HOST:$CONF_DEST" || { echo "Failed to copy configuration file to $REMOTE_HOST. Ensure you have the correct permissions."; exit 1; }

        # Set executable permissions for the script
        ssh "$REMOTE_HOST" "chmod +x $SCRIPT_DEST" || { echo "Failed to set executable permissions on $REMOTE_HOST. Ensure you have the correct permissions."; exit 1; }

        echo "Installation completed on $REMOTE_HOST."
        exit 0
        ;;
    --run|--watch)
        echo "Connecting to $REMOTE_HOST and executing conntrack.sh..."

        # Determine the command to execute based on the action
        if [ "$ACTION" == "--run" ]; then
            remote_command="/usr/bin/conntrack.sh"
        else
            remote_command="tail -f $LOGFILE"
        fi

        # Execute the command on the remote host and process its output
        ssh -o ServerAliveInterval=60 "$REMOTE_HOST" "$remote_command" | while IFS= read -r line; do
            # Skip empty lines
            [ -z "$line" ] && continue
            
            # Get appropriate icon based on line content
            icon=$(get_notification_icon "$line")
            
            # Get hostname for the notification title
            remote_hostname=$(echo "$REMOTE_HOST" | cut -d@ -f2)
            
            # Print
            echo "$line"

            # Send desktop notification
            notify-send --icon="$icon" \
                        --hint=int:transient:1 \
                        "conntrack_sh @$remote_hostname" \
                        "$line"

            if [ "$BROADCAST" = true ]; then
                echo "conntrack.sh @$(hostname): $line" | wall 2>/dev/null
            fi
        done

        # Error handling
        if [ $? -ne 0 ]; then
            echo "Lost connection to $REMOTE_HOST"
            exit 1
        fi
        exit 0
        ;;
    *)
        usage
        ;;
esac
