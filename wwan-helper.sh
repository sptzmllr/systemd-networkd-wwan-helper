#!/bin/bash

set -euo pipefail

if [[ "$EUID" != "0" ]]; then
    printf "Only root can manipulate LTE connection\n" 1>&2
    exit 1
fi

# Make here ajusments 
NETDEV=wwp0s20f0u6
CDCDEV=/dev/cdc-wdm0
CONFIG="/var/run/systemd/network/50-$NETDEV.network.d/online.conf"

# This PIN is an initial Value it is rewrite this in the next line
# and apend a '# gitignore' without the space
PIN=1234
APN=internet


# parse_* functions based on https://gist.github.com/zakx/2336f9c551416a92e3172b6ac7c88ade
ipv4_addresses=()
ipv4_gateway=""
ipv4_dns=()
ipv4_mtu=""
ipv6_addresses=()
ipv6_gateway=""
ipv6_dns=()
ipv6_mtu=""

function parse_ip {
    # IP [0]: '10.134.203.177/30'
    local line_re="IP \[([0-9]+)\]: '(.+)'"
    local input="$1"
    if [[ $input =~ $line_re ]]; then
        local ip_cnt=${BASH_REMATCH[1]}
        local ip=${BASH_REMATCH[2]}
    fi
    echo "$ip"
}

function parse_gateway {
    # Gateway: '10.134.203.178'
    local line_re="Gateway: '(.+)'"
    local input="$1"
    if [[ $input =~ $line_re ]]; then
        local gw=${BASH_REMATCH[1]}
    fi
    echo "$gw"
}

function parse_dns {
    # DNS [0]: '10.134.203.177/30'
    local line_re="DNS \[([0-9]+)\]: '(.+)'"
    local input="$1"
    if [[ $input =~ $line_re ]]; then
        local dns_cnt=${BASH_REMATCH[1]}
        local dns=${BASH_REMATCH[2]}
    fi
    echo "$dns"
}

function parse_mtu {
    # MTU: '1500'
    local line_re="MTU: '([0-9]+)'"
    local input="$1"
    if [[ $input =~ $line_re ]]; then
        local mtu=${BASH_REMATCH[1]}
    fi
    echo "$mtu"
}

function parse_mbim {
    while read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue

        case "$line" in
            *"IPv4 configuration available: 'none'"*)
                state="start"
                continue
                ;;
            *"IPv6 configuration available: 'none'"*)
                state="start"
                continue
                ;;
            *"IPv4 configuration available"*)
                state="ipv4"
                continue
                ;;
            *"IPv6 configuration available"*)
                state="ipv6"
                continue
                ;;
            *)
                ;;
        esac

        case "$state" in
            "ipv4")
                case "$line" in
                    *"IP"*)
                        row=$(parse_ip "$line")
                        ipv4_addresses+=("$row")
                        continue
                        ;;
                    *"Gateway"*)
                        row=$(parse_gateway "$line")
                        ipv4_gateway="$row"
                        continue
                        ;;
                    *"DNS"*)
                        row=$(parse_dns "$line")
                        ipv4_dns+=("$row")
                        continue
                        ;;
                    *"MTU"*)
                        row=$(parse_mtu "$line")
                        ipv4_mtu="$row"
                        continue
                        ;;
                    *)
                        continue
                        ;;
                esac
                ;;
            "ipv6")
                case "$line" in
                    *"IP"*)
                        row=$(parse_ip "$line")
                        ipv6_addresses+=("$row")
                        continue
                        ;;
                    *"Gateway"*)
                        row=$(parse_gateway "$line")
                        ipv6_gateway="$row"
                        continue
                        ;;
                    *"DNS"*)
                        row=$(parse_dns "$line")
                        ipv6_dns+=("$row")
                        continue
                        ;;
                    *"MTU"*)
                        row=$(parse_mtu "$line")
                        ipv6_mtu="$row"
                        continue
                        ;;
                    *)
                        continue
                        ;;
                esac
                ;;
            *)
                continue
                ;;
        esac
    done <<< $(mbimcli -p -d $CDCDEV --query-ip-configuration=0)

    local config_file="$1"

    printf "[Match]\nName=%s\n\n" $NETDEV >> $config_file
    printf "[Link]\nUnmanaged=false\n\n" >> $config_file

    printf "[Network]\n" >> $config_file
    printf "Description=LTE (connected)\n\n" >> $config_file
    printf "IPv6AcceptRA=false\n" >> $config_file
    printf "LinkLocalAddressing=false\n" >> $config_file
    printf "LLMNR=false\n" >> $config_file
    printf "LLDP=false\n" >> $config_file
    printf "#DNSOverTLS=false\n\n" >> $config_file

    if [[ "${#ipv6_addresses[@]}" > 0 ]]; then
        printf "Gateway=%s\n" "$ipv6_gateway" >> $config_file
        printf "Address=%s\n" "${ipv6_addresses[@]}" >> $config_file
        if [[ "${#ipv6_dns[@]}" > 0 ]]; then
            for a in "${ipv6_dns[@]}"; do
                printf "#DNS=%s\n" "$a" >> $config_file
            done
        fi
        if [[ -n "$ipv6_mtu" ]]; then
            printf "IPv6MTUBytes=%s\n" "$ipv6_mtu" >> $config_file
        fi
	printf "\n" >> $config_file
    fi

    if [[ "${#ipv4_addresses[@]}" > 0 ]]; then
        printf "Gateway=%s\n" "$ipv4_gateway" >> $config_file
        printf "Address=%s\n" "${ipv4_addresses[@]}" >> $config_file
        if [[ "${#ipv4_dns[@]}" > 0 ]]; then
            for a in "${ipv4_dns[@]}"; do
                printf "#DNS=%s\n" "$a" >> $config_file
            done
        fi
        if [[ -n "$ipv4_mtu" ]]; then
            printf "#MTUBytes=%s\n" "$ipv4_mtu" >> $config_file
        fi
	printf "\n" >> $config_file
    fi

    printf "#EOF\n" >> $config_file
}


case "$1" in
    "info")
        mbimcli -p -d $CDCDEV --query-subscriber-ready-status
        mbimcli -p -d $CDCDEV --query-registration-state
        mbimcli -p -d $CDCDEV --query-signal-state
        networkctl status $NETDEV -s
        resolvectl status $NETDEV
        ;;

    "test")
        ping -c 5 -4 -I $NETDEV dns.google
        ping -c 5 -6 -I $NETDEV dns.google
        ;;

    "start")
        rfkill unblock wwan
        mbimcli -p -d $CDCDEV --enter-pin=$PIN
        printf "Waiting 15 seconds for LTE registration...\n"
        sleep 15

        mbimcli -p -d $CDCDEV --connect=apn=$APN

        trap '{ rm -f "$tmpfile"; }' EXIT
        tmpfile=$(mktemp /tmp/lte-config.XXXXXX)
        parse_mbim "$tmpfile"

        install -D -o systemd-network -g systemd-network -m 644 "$tmpfile" "$CONFIG"
        networkctl reload
        ;;

    "stop")
        ip link set $NETDEV down

        rm "$CONFIG"
        networkctl reload

        mbimcli -p -d $CDCDEV --disconnect
        rfkill block wwan
        ;;

    *)
        printf "%s (start|stop|info|test)\n" "$(basename $0)"
        ;;
esac
