#!/bin/bash
# conntrack.sh - Monitor network connections for suspicious activity

# print every command before executing it
#set -x

## Default confoguration

# User who shall receive notify-send messages (use false if you want to turn off notifications)
NOTIFY_SEND_USER="`whoami`"

# Define your whitelist of process names
WHITELISTED_PROCESSES=("firefox" "ssh" "thunderbird")

# Define your whitelisted remote IPs
WHITELISTED_REMOTE_IPS=()

# Define critical ports
CRITICAL_PORTS=("80" "443")

# Show unknown processes
SHOW_UNKNOWN_PROCESSES=false

# DEBUG
DEBUG=false

# Monitor all protocols, instead of just TCP
PROTO_ALL=false

# Monitor only critical ports
CRITICAL_ONLY=false

# Broadcast notifications to all terminals
BROADCAST=false

# Log file for non-whitelisted processes
LOGFILE="/var/log/conntrack_sh.log"

# Temporary file for netstat output
NETSTAT_FILE="/tmp/conntrack_sh_netstat.log"

# Temporary file for storing process IDs of processes we reported before
PID_DOUBLES_FILE="`mktemp`"

# Temporary file for storing remote IPs we reported before
IP_DOUBLES_FILE="`mktemp`"

# Have a temporary file for storing immediate doubles
FILTER_DOUBLES_FILE="`mktemp`"

## Load config file
CONFIG_FILE="/etc/conntrack_sh.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

## Parse command line parameters
show_defaults() {
    echo "Current configuration (including defaults and loaded config file):"
    echo "  SHOW_UNKNOWN_PROCESSES: $SHOW_UNKNOWN_PROCESSES"
    echo "  DEBUG: $DEBUG"
    echo "  BROADCAST: $BROADCAST"
    echo "  PROTO_ALL: $PROTO_ALL"
    echo "  CRITICAL_ONLY: $CRITICAL_ONLY"
    echo "  WHITELISTED_PROCESSES: ${WHITELISTED_PROCESSES[*]}"
    echo "  WHITELISTED_REMOTE_IPS: ${WHITELISTED_REMOTE_IPS[*]}"
    echo "  CRITICAL_PORTS: ${CRITICAL_PORTS[*]}"
    echo "  LOGFILE: $LOGFILE"
    echo "  NETSTAT_FILE: $NETSTAT_FILE"
    echo "  CONFIG_FILE: $CONFIG_FILE"
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            echo "usage: $0 [options]"
            echo "  -h, --help: Show this help message"
            echo "  --show-defaults: Display default configuration"
            echo "  --show-unknown=[true|false]: Enable or disable full reporting mode, which also shows unknown processes"
            echo "  --debug=[true|false]: Enable or disable debug mode"
            echo "  --broadcast=[true|false]: Enable or disable sending notifications to all terminals via wall"
            echo "  --proto-all=[true|false]: Include all protocols (instead of just tcp)"
            echo "  --filter-critical=[true|false]: Only show connections on critical ports"
            exit 0
            ;;
        --show-unknown=*)
            SHOW_UNKNOWN_PROCESSES="${key#*=}"
            shift
            ;;
        --debug=*)
            DEBUG="${key#*=}"
            shift
            ;;
        --broadcast=*)
            BROADCAST="${key#*=}"
            shift
            ;;
        --PROTO_ALL=*)
            PROTO_ALL="${key#*=}"
            shift
            ;;
        --filter-critical=*)
            CRITICAL_ONLY="${key#*=}"
            shift
            ;;
        --show-defaults)
            show_defaults
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Ensure boolean values are valid
for var in SHOW_UNKNOWN_PROCESSES DEBUG BROADCAST PROTO_ALL CRITICAL_ONLY; do
    if [[ "${!var}" != "true" && "${!var}" != "false" ]]; then
        echo "Invalid value for $var: ${!var}. Allowed values are 'true' or 'false'."
        exit 1
    fi
done

## Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

## Prevent multiple instances
#LOCKFILE="/tmp/conntrack-sh.lock"
#if [ -e "$LOCKFILE" ]; then
#    echo "Script is already running."
#    exit 1
#fi
#touch "$LOCKFILE"

## Program logic init
# Initialize the PID_DOUBLES_FILE to be able to filter for connections that existed from the start
netstat -tnp | tail -n +3 | awk '{print $NF}' | grep -P '\d+/.+' | sort | uniq > "$PID_DOUBLES_FILE"

# Ensure log file exists and is writable
touch "$LOGFILE" || { echo "Cannot create log file"; exit 1; }

# Function to check if a process name or remote IP is in the whitelist
is_whitelisted() {
    local process_name="$1"
    local remote_ip="$2"

    for whitelist_name in "${WHITELISTED_PROCESSES[@]}"; do
        if [[ "$process_name" == "$whitelist_name" ]]; then
            return 0
        fi
    done

    for whitelist_name in "${WHITELISTED_REMOTE_IPS[@]}"; do
        if [[ "$remote_ip" == "$whitelist_name" ]]; then
            return 0
        fi
    done

    return 1
}

## Function to clean up and exit on SIGTERM or SIGINT
cleanup() {
    echo "Stopping script..."
    pkill -P $$ conntrack
    # Remove lock file
    #rm -f "$LOCKFILE"
    exit 0
}

# Trap termination signals
trap cleanup SIGTERM SIGINT

echo "Starting connection monitoring..."

## Monitor network connections using conntrack
if [ "$PROTO_ALL" = true ]; then
    conntrackargs=""
else
    conntrackargs="--proto tcp"
fi

conntrack -E -o extended $conntrackargs | while read -r line; do
    # Only process new connections
    #if [[ "$line" == *"[NEW]"* ]]; then
        ## Extract source and destination information
        proto=$(echo "$line" | sed -n 's/.* \(tcp\|PROTO_ALL\) .*/\1/p' | tr -d '\n')
        src_ip=$(echo "$line" | sed -n 's/.*src=\([0-9a-z\:.]*\).*/\1/p' | tail -n1 | sed 's/::.*//')
        dst_ip=$(echo "$line" | sed -n 's/.*dst=\([0-9a-z\:.]*\).*/\1/p' | tail -n1 | sed 's/::.*$//')
        src_port=$(echo "$line" | sed -n 's/.*sport=\([0-9]*\).*/\1/p' | tail -n1)
        dst_port=$(echo "$line" | sed -n 's/.*dport=\([0-9]*\).*/\1/p' | tail -n1)

        ## Find information about the remote IP address
        org_name="" #$(whois "$src_ip::1" | grep -Ei 'orgname|netname|role|address' | head -n1 | awk -F ':' '{print $2}' | xargs | tr -d '\n')

        ## Find the process behind a connection using netstat
		netstat -tnp > $NETSTAT_FILE 2>/dev/null
        pid=$(grep -w "$src_ip" "$NETSTAT_FILE" | grep -w ":$src_port" | awk '{print $NF}' | head -n1 | grep -P '^\d+/[^ ]+$')
        
        # Check whether $pid is numeric and non-empty
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            continue
        fi

        ## Do not show immediate doubles
        last_double=$(cat $FILTER_DOUBLES_FILE)
        filter_info="$pid $proto $src_ip:$src_port -> $dst_ip" # Often we have doubles with same remote src_port and varying local dst_port, so dst_port is not used for filtering
        echo "$filter_info" > $FILTER_DOUBLES_FILE
        if [ "$last_double" = "$filter_info" ]; then
            continue
        fi

        # Check if remote IP was previously reported with the given protocol and port
        if grep -q "$proto $src_ip $src_port" "$IP_DOUBLES_FILE"; then
            continue
        fi
        echo "$proto $src_ip $src_port" >> "$IP_DOUBLES_FILE"
        
        ## DEBUG
        if [ "$DEBUG" = true ]; then
            echo "DEBUG: line: $line"
            echo "DEBUG: srcip $src_ip (org: ${org_name}) srcport $src_port"
            echo "DEBUG: pid $pid | pid search criteria for netstat: $src_ip:$src_port"
        fi
        
        ## Create nice log output based while considering our filter logic
        timestamp=$(date "+%Y-%m-%d %H:%M:%S" | tr -d '\n')     

        if [[ -n "$pid" ]]; then # Only continue if process ID could be determined, otherwise the log output is of low value
            src_pid=$(echo "$pid" | cut -d'/' -f1 | tr -d '\n')
            process_name=$(echo "$pid" | cut -d'/' -f2 | tr -d '\n')

            # Check if process was previously reported, i.e., is listed in $PID_DOUBLES_FILE
            if [ ! "$SHOW_UNKNOW_PROCESSES" ]; then
                if grep -q "$src_pid/$process_name" "$PID_DOUBLES_FILE"; then
                    continue
                fi
            fi

            # Check if src_port or dst_port is in CRITICAL_PORTS
            if [[ " ${CRITICAL_PORTS[*]} " =~ " ${src_port} " ]] || [[ " ${CRITICAL_PORTS[*]} " =~ " ${dst_port} " ]]; then
                # Highlight console line in orange
                echo -en "\033[1;33m"  # Orange color
                echo -n "! "

                # Pick a warning icon for notify-send
                notify_icon="dialog-warning"
            fi
            
            # Check if the process and IP are NOT whitelisted
            if ! is_whitelisted "$process_name" "$src_ip"; then
                # Highlight console line in red
                echo -en "\033[1;31m"  # Red color
                echo -n "!! "
                
                # Pick an error icon for notify-send
                notify_icon="dialog-error"
            else
                # Highlight console line in green
                echo -en "\033[1;32m"  # Green color
                echo -n "# "
                
                # Pick a greenish ok icon for notify-send
                notify_icon="dialog-information"
            fi

            log_line="${timestamp} - ${proto} - ${src_ip}:${src_port} (org: ${org_name}) -> ${dst_ip}:${dst_port} - Process: ${process_name} (PID: ${src_pid})"
            echo "$src_pid/$process_name" >> $PID_DOUBLES_FILE
        elif [ "$SHOW_UNKNOWN_PROCESSES" = true ]; then
            # Check if src_port or dst_port is in CRITICAL_PORTS
            if [[ " ${CRITICAL_PORTS[*]} " =~ " ${src_port} " ]] || [[ " ${CRITICAL_PORTS[*]} " =~ " ${dst_port} " ]]; then
                echo -en "\033[1;31m"  # Red color
                echo -n "!! "
                
                # Pick an error icon for notify-send
                notify_icon="dialog-error"
            elif [ "$CRITICAL_ONLY" = true ]; then
                continue
            else
                notify_icon="dialog-information"
            fi

            log_line="${timestamp} - ${proto} - ${src_ip}:${src_port} (org: ${org_name}) -> ${dst_ip}:${dst_port} - Process: Unknown"
        else
            log_line=""
            continue
        fi

#        # Log the line to the log file and show it in the console
        echo "$log_line" >> "$LOGFILE"
        echo -en "\t"
        echo $log_line
        # Reset console color
        echo -en "\033[0m"

        # Send notification using notify-send
        if [ "$NOTIFY_SEND_USER" != false ]; then
            sudo -u "$USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$NOTIFY_SEND_USER")/bus notify-send --icon=$notify_icon "conntrack.sh @`hostname`" "$log_line" 2>/dev/null
        fi

        # Send notification to all terminals using wall
        if [ "$BROADCAST" = true ]; then
            echo "conntrack.sh @`hostname`: $log_line" | wall 2>/dev/null
        fi
    #fi
done
