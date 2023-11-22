#!/bin/bash

stderr(){ echo "$@" >/dev/stderr; }
error(){ echo "Error: $@" >/dev/stderr; }
cancel(){ echo "Canceled." >/dev/stderr; exit 2; }
fault(){ test -n "$1" && error $1; echo "Exiting." >/dev/stderr; exit 1; }
print_array(){ printf '%s\n' "$@"; }
confirm() {
    ## Confirm with the user.
    local default=$1; local prompt=$2; local question=${3:-". Proceed?"}
    if [[ $default == "y" || $default == "yes" || $default == "ok" ]]; then
        dflt="Y/n"
    else
        dflt="y/N"
    fi
    read -e -p $'\e[32m?\e[0m '"${prompt}${question} (${dflt}): " answer
    answer=${answer:-${default}}
    if [[ ${answer,,} == "y" || ${answer,,} == "yes" || ${answer,,} == "ok" ]]; then
        return 0
    else
        return 1
    fi
}
ask() {
    local __prompt="${1}"; local __var="${2}"; local __default="${3}"
    while true; do
        read -e -p "${__prompt}"$'\x0a\e[32m:\e[0m ' -i "${__default}" ${__var}
        export ${__var}
        [[ -z "${!__var}" ]] || break
    done
}
check_var(){
    local __missing=false
    local __vars="$@"
    for __var in ${__vars}; do
        if [[ -z "${!__var}" ]]; then
            error "${__var} variable is missing."
            __missing=true
        fi
    done
    if [[ ${__missing} == true ]]; then
        fault
    fi
}
check_num(){
    local var=$1
    check_var var
    if ! [[ ${!var} =~ ^[0-9]+$ ]] ; then
        fault "${var} is not a number: '${!var}'"
    fi
}
element_in_array () {
  local e match="$1"; shift;
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}
get_bridges() {
    readarray -t INTERFACES < <(cat /etc/network/interfaces | grep -Po "^iface \K(vmbr[0-9]*)")
    stderr ""
    stderr "Currently configured bridges:"
    print_array "${INTERFACES[@]}"
}
prefix_to_netmask () {
    #thanks https://forum.archive.openwrt.org/viewtopic.php?id=47986&p=1#p220781
    set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
    [ $1 -gt 1 ] && shift $1 || shift
    echo ${1-0}.${2-0}.${3-0}.${4-0}
}
validate_ip_address () {
    #thanks https://stackoverflow.com/a/21961938
    echo "$@" | grep -o -E  '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)' >/dev/null
}
validate_ip_network() {
    #thanks https://stackoverflow.com/a/21961938
    PREFIX=$(echo "$@" | grep -o -P "/\K[[:digit:]]+$")
    if [[ "${PREFIX}" -ge 0 ]] && [[ "${PREFIX}" -le 32 ]]; then
        echo "$@" | grep -o -E  '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/[[:digit:]]+' >/dev/null
    else
        return 1
    fi
}
debug_var() {
    local var=$1
    check_var var
    echo "## DEBUG: ${var}=${!var}" > /dev/stderr
}

new_interface() {
    local INTERFACE IP_CIDR IP_ADDRESS NETMASK COMMENT OTHER_BRIDGE SYSTEMD_UNIT SYSTEMD_SERVICE
    get_bridges
    set -e
    echo
    confirm yes "Do you want to create a new NAT bridge" "?"  || return 1
    echo
    ask "Enter the existing bridge to NAT from" OTHER_BRIDGE vmbr0
    if ! element_in_array "$OTHER_BRIDGE" "${INTERFACES[@]}"; then
        fault "Sorry, ${OTHER_BRIDGE} is not a valid bridge (it does not exist)"
    fi
    ask "Enter a unique number for the new bridge (don't write the vmbr prefix)" BRIDGE_NUMBER
    check_num BRIDGE_NUMBER
    INTERFACE="vmbr${BRIDGE_NUMBER}"

    if element_in_array "$INTERFACE" "${INTERFACES[@]}"; then
        fault "Sorry, ${INTERFACE} already exists."
    fi
    echo
    echo "Configuring new interface: ${INTERFACE}"
    ask "Enter the static IP address and network prefix in CIDR notation for ${INTERFACE}:" IP_CIDR "10.${BRIDGE_NUMBER}.0.1/24"
    if ! validate_ip_network "${IP_CIDR}"; then
        fault "Bad IP address / network"
    fi
    echo
    debug_var IP_CIDR
    IP_ADDRESS=$(echo "$IP_CIDR" | cut -d "/" -f 1)
    NETMASK="$(prefix_to_netmask $(echo "$IP_CIDR" | cut -d "/" -f 2))"
    if ! validate_ip_address "${IP_ADDRESS}"; then
        fault "Bad IP address: ${IP_ADDRESS}"
    fi
    if ! validate_ip_address "${NETMASK}"; then
        fault "Bad netmask: ${NETMASK}"
    fi
    debug_var IP_ADDRESS
    debug_var NETMASK
    ask "Enter the description for this interface" COMMENT "NAT ${IP_CIDR} bridged to ${OTHER_BRIDGE}"
    cat <<EOF >> /etc/network/interfaces

auto ${INTERFACE}
iface ${INTERFACE} inet static
        address  ${IP_ADDRESS}
        netmask  ${NETMASK}
        bridge_ports none
        bridge_stp off
        bridge_fd 0
        post-up echo 1 > /proc/sys/net/ipv4/ip_forward
        post-up   iptables -t nat -A POSTROUTING -s '${IP_CIDR}' -o ${OTHER_BRIDGE} -j MASQUERADE
        post-down iptables -t nat -D POSTROUTING -s '${IP_CIDR}' -o ${OTHER_BRIDGE} -j MASQUERADE
#${COMMENT}

EOF
    echo "Wrote /etc/network/interfaces"
    ifup "${INTERFACE}"
    echo "Activated ${INTERFACE}"
}

activate_iptables_rules() {
    IPTABLES_RULES=/etc/network/my-iptables-rules.sh
    if [[ ! -f ${IPTABLES_RULES} ]]; then
        cat <<EOF > ${IPTABLES_RULES}
#!/bin/sh
## Create your DNAT port forwarding rules here:
## Example: forward incoming TCP port 2222 from vmbr0 to a VM with ip 10.51.0.2 on port 22
#iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 2222 -j DNAT --to 10.51.0.2:22
EOF
        chmod a+x ${IPTABLES_RULES}
        echo "Wrote iptables rules file with commented examples: ${IPTABLES_RULES}"
    else
        echo "Found existing iptables rules file: ${IPTABLES_RULES}"
    fi
    SYSTEMD_UNIT="my-iptables-rules"
    SYSTEMD_SERVICE="/etc/systemd/system/${SYSTEMD_UNIT}.service"
    if [[ ! -f ${SYSTEMD_SERVICE} ]]; then
        cat <<EOF > ${SYSTEMD_SERVICE}
[Unit]
Description=Load iptables ruleset from ${IPTABLES_RULES}
ConditionFileIsExecutable=${IPTABLES_RULES}
After=network-online.target

[Service]
Type=forking
ExecStart=${IPTABLES_RULES}
TimeoutSec=0
RemainAfterExit=yes
GuessMainPID=no

[Install]
WantedBy=network-online.target
EOF
    fi
    systemctl daemon-reload
    if [[ "$(systemctl is-enabled my-iptables-rules)" != "enabled" ]]; then
        confirm yes "Would you like to enable the iptables rules in ${IPTABLES_RULES} now and on boot" "?" && systemctl enable --now ${SYSTEMD_SERVICE}
        echo "Remember: no rules are defined by default! You need to manually edit the rules file and/or uncomment the examples."
    fi
}

main() {
    new_interface || true
    activate_iptables_rules
}

main
