#!/bin/sh

# Keep the x86 appliance's physical cabling stable on a fresh installation:
# eth0 is WAN and eth1 is LAN.  ImmortalWrt's generic x86 defaults use the
# opposite layout.  Only rewrite that exact untouched default so upgrades or
# restored/custom network configurations are never overwritten.

LOGFILE="/etc/uci-defaults-log.txt"

log_message() {
    echo "98-x86-interface-roles: $*" >>"$LOGFILE"
}

case "$(uname -m 2>/dev/null)" in
    x86_64|amd64)
        ;;
    *)
        exit 0
        ;;
esac

if [ ! -e /sys/class/net/eth0 ] || [ ! -e /sys/class/net/eth1 ]; then
    log_message "eth0 or eth1 is missing; leaving network configuration unchanged"
    exit 0
fi

wan_device=$(uci -q get network.wan.device 2>/dev/null)
if [ "$wan_device" != "eth1" ]; then
    log_message "WAN is already $wan_device instead of the generic eth1 default; skipping"
    exit 0
fi

br_lan_section=""
for section in $(uci -q show network 2>/dev/null | sed -n 's/^network\.\([^=]*\)=device$/\1/p'); do
    if [ "$(uci -q get "network.$section.name" 2>/dev/null)" = "br-lan" ]; then
        br_lan_section="$section"
        break
    fi
done

if [ -z "$br_lan_section" ]; then
    log_message "br-lan device section was not found; skipping"
    exit 0
fi

lan_ports=$(uci -q get "network.$br_lan_section.ports" 2>/dev/null)
lan_ports=$(echo "$lan_ports" | awk '{$1=$1; print}')
if [ "$lan_ports" != "eth0" ]; then
    log_message "br-lan ports are already customized ($lan_ports); skipping"
    exit 0
fi

revert_network() {
    uci -q revert network
    log_message "failed to apply interface roles; reverted pending network changes"
    exit 1
}

uci set network.wan.device='eth0' || revert_network

wan6_device=$(uci -q get network.wan6.device 2>/dev/null)
if [ "$wan6_device" = "eth1" ]; then
    uci set network.wan6.device='eth0' || revert_network
fi

uci -q delete "network.$br_lan_section.ports" || revert_network
uci add_list "network.$br_lan_section.ports=eth1" || revert_network
uci commit network || revert_network

log_message "applied stable x86 mapping: WAN=eth0, LAN=eth1"
exit 0
