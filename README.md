# conntrack.sh

![License](https://img.shields.io/github/license/jvm123/conntrack.sh?cache-control=no-cache)
![ShellCheck](https://github.com/jvm123/conntrack.sh/actions/workflows/shellcheck.yml/badge.svg)

`conntrack.sh` is a shell script designed to facilitate the continuous manual monitoring of network connections for suspicious activity. It wraps the conntrack utility specifically for this use case and uses some aggressive filtering to reduce the number of logged events. Notifications can be logged, shown on the console and optionally sent as terminal broadcast message or as desktop notification via notify-send.

This is especially useful on a developer system, to observe anomalies during the testing of not fully trusted applications or libraries.

## Features
- Monitors network connections in real-time using the conntrack tool.
- Filters log entries aggressively, to reduce the output to a level where it is sustainable as a tool that can run continuously in the background. Configurable process name and IP whitelists.
- Logs remote IPs / ports that connections were established with. Tries to identify the process name making that initiated the connection.
- Supports highlighting connections as critical, based on configurable TCP ports.
- Send desktop notifications.
- Configurable via a configuration file.

## Installation

1. Clone the repository and cd into it.

2. Feel free to modify the conf file to your liking first.

3. Run the installation script:
   ```bash
   sudo ./install.sh
   ```

   This will:
   - Copy the configuration file to `/etc/conntrack_sh.conf`.
   - Copy the main script to `/usr/bin/conntrack.sh`.
   - Copy the ssh convenience script to `/usr/bin/conntrack_ssh.sh`.

4. To configure autostart at boot on Ubuntu, run
   ```bash
   sudo ./install.sh --systemd
   ```

## Usage
Run the script with optional parameters:
```bash
sudo conntrack.sh [options]
```

The parameters include
- `-h, --help`: Display help message
- `--show-defaults`: Display the default configuration.
- `--show-unknown=[true|false]`: Enable or disable full reporting mode, which also shows unknown processes.
- `--debug=[true|false]`: Enable or disable debug mode.
- `--broadcast=[true|false]`: Enable or disable sending notifications to all users.
- `--proto-all=[true|false]`: Include all protocols (instead of just TCP).
- `--filter-critical=[true|false]`: Only show connections on critical ports.

A log file is written to `/var/log/conntrack_sh.log`.

## Configuration

The script uses a configuration file located at `/etc/conntrack_sh.conf`. Below are the configurable options:

- **LOGFILE**: Log file path
- **WHITELISTED_PROCESSES**: Array of process names to whitelist (e.g., `("firefox" "ssh")`).
- **WHITELISTED_REMOTE_IPS**: Array of remote IPs to whitelist.
- **CRITICAL_PORTS**: Array of critical ports to monitor (e.g., `("80" "443")`).
- **SHOW_UNKNOWN_PROCESSES**: Whether to log unknown processes (`true` or `false`).
- **DEBUG**: Enable debug mode (`true` or `false`).
- **PROTO_ALL**: Monitor all protocols (`true`) or only TCP (`false`).
- **CRITICAL_ONLY**: Monitor only critical ports (`true` or `false`).
- **BROADCAST**: Broadcast notifications to all terminals (`true` or `false`).

## Monitoring remote systems

A helper script `conntrack_ssh.sh` is included for convenience. With it, network traffic on remote systems can be monitored as well. You could have done this without this helper script, its primary use case is to create local notify-send messages for events that were recorded on the remote system.

- `-h, --help`: Display help message
- `--install user@hostname"`: Install the script and config file remotely
- `--run user@hostname [logfile]"`: Execute the script remotely and show the output
- `--watch user@hostname [logfile]"`: Assume that the script is already running remotely, but hook to its logfile to show the output locally

## Limitations

- Requires root privileges to run.
- May generate false positives if the configuration is not properly tuned.
- May overlook a lot of stuff, as it is a convenience wrapper that tries to filter "uninteresting" activities. This comes with the risk of overlooking some connections.
- Sees only those network connections that `conntrack` sees. E.g., if nftables is not set up appropriately, all or only IPv6 traffic may go unreported.
- Events can sometimes show up with a considerable delay, which complicates testing a bit.

## Alternatives

You can always get more logs and smarter filtering with existing tools.

- tcpdump -i eth0 -A
- strace
- nethogs
- [conntrack-logger](https://github.com/mk-fg/conntrack-logger)

## TODO

- Reintroduce host name resolution / whois output
- Confirm ways to increase success rate in determination of process name
- Become more flexible with the filter configuration

## References

- [conntrack](https://conntrack-tools.netfilter.org/manual.html#conntrack): A tool for managing and monitoring network connections.
