#!/bin/bash

SYSTEMD_UNIT="my-iptables-rules"
SYSTEMD_SERVICE="/etc/systemd/system/${SYSTEMD_UNIT}.service"
IPTABLES_RULES_SCRIPT="/etc/network/${SYSTEMD_UNIT}.sh"

set -eo pipefail
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
    local INTERFACE IP_CIDR IP_ADDRESS NETMASK COMMENT OTHER_BRIDGE
    get_bridges
    set -e
    echo
    confirm no "Do you want to create a new NAT bridge" "?"  || return 1
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
    if [[ ! -f ${IPTABLES_RULES_SCRIPT} ]]; then
        fault "iptables script not found: ${IPTABLES_RULES_SCRIPT}"
    fi
    if [[ ! -f ${SYSTEMD_SERVICE} ]]; then
        cat <<EOF > ${SYSTEMD_SERVICE}
[Unit]
Description=Load iptables ruleset from ${IPTABLES_RULES_SCRIPT}
ConditionFileIsExecutable=${IPTABLES_RULES_SCRIPT}
After=network-online.target

[Service]
Type=forking
ExecStart=${IPTABLES_RULES_SCRIPT}
TimeoutSec=0
RemainAfterExit=yes
GuessMainPID=no

[Install]
WantedBy=network-online.target
EOF
    fi
    systemctl daemon-reload
    if [[ "$(systemctl is-enabled ${SYSTEMD_UNIT})" != "enabled" ]]; then
        confirm yes "Would you like to enable the iptables rules in ${IPTABLES_RULES_SCRIPT} now and on boot" "?" && systemctl enable ${SYSTEMD_UNIT} && echo "Systemd unit enabled: ${SYSTEMD_UNIT}" && systemctl restart ${SYSTEMD_UNIT} && echo "NAT rules applied: ${IPTABLES_RULES_SCRIPT}"
    else
        echo "Systemd unit already enabled: ${SYSTEMD_UNIT}"
        systemctl restart ${SYSTEMD_UNIT} && echo "NAT rules applied: ${IPTABLES_RULES_SCRIPT}"
    fi
}

get_port_forward_rules() {
    # Retrieve the PORT_FORWARD_RULES array from the iptables script:
    if [[ ! -f "${IPTABLES_RULES_SCRIPT}" ]]; then
        return
    fi
    IFS=' ' read -ra rule_parts < <(grep -P -o "^PORT_FORWARD_RULES=\(\K(.*)\)$" ${IPTABLES_RULES_SCRIPT} | tr -d '()' | tail -1)
    for part in "${rule_parts[@]}"; do
        echo "${part}"
    done
}

create_iptables_rules() {
    readarray -t PORT_FORWARD_RULES <<< "$@"
    if [[ "${#PORT_FORWARD_RULES[@]}" -eq "0" ]]; then
        fault "PORT_FORWARD_RULES array is empty!"
    fi
    cat <<'EOF' > ${IPTABLES_RULES_SCRIPT}
#!/bin/bash
## Script to configure the DNAT port forwarding rules:
## This script should not be edited by hand, it is generated from proxmox_nat.sh

error(){ echo "Error: $@"; }
fault(){ test -n "$1" && error $1; echo "Exiting." >/dev/stderr; exit 1; }
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
purge_port_forward_rules() {
    iptables-save | grep -v "Added by proxmox_nat.sh" | iptables-restore
}
apply_port_forward_rules() {
    ## Validate all the rules:
    set -e
    if [[ "${#PORT_FORWARD_RULES[@]}" -le 1 ]] && [[ "${PORT_FORWARD_RULES[0]}" == "" ]]; then
        error "PORT_FORWARD_RULES array is empty!"
        exit 0
    fi
    for rule in "${PORT_FORWARD_RULES[@]}"; do
        echo "debug: ${rule}"
        IFS=':' read -ra rule_parts <<< "$rule"
        if [[ "${#rule_parts[@]}" != "5" ]]; then
            fault "Invalid rule (there should be 5 parts): ${rule}"
        fi
    done
    ## Apply all the rules:
    for rule in "${PORT_FORWARD_RULES[@]}"; do
        IFS=':' read -ra rule_parts <<< "$rule"
        local INTERFACE PROTOCOL IN_PORT DEST_IP DEST_PORT
        INTERFACE="${rule_parts[0]}"
        PROTOCOL="${rule_parts[1]}"
        IN_PORT="${rule_parts[2]}"
        DEST_IP="${rule_parts[3]}"
        DEST_PORT="${rule_parts[4]}"
        check_var INTERFACE PROTOCOL IN_PORT DEST_IP DEST_PORT
        iptables -t nat -A PREROUTING -i ${INTERFACE} -p ${PROTOCOL} \
            --dport ${IN_PORT} -j DNAT --to ${DEST_IP}:${DEST_PORT} \
            -m comment --comment "Added by proxmox_nat.sh"
    done
}
EOF
    cat <<EOF >> ${IPTABLES_RULES_SCRIPT}
## PORT_FORWARD_RULES is an array of port forwarding rules,
## each item in the array contains five elements separated by colon:
## INTERFACE:PROTOCOL:OUTSIDE_PORT:IP_ADDRESS:DEST_PORT

## * IMPORTANT: PORT_FORWARD_RULES should all be on ONE LINE with no line breaks.

## Here is an example with two rules (commented out), and explained:
##  * For any TCP packet on port 2222 coming from vmbr0, forward to 10.15.0.2 on port 22
##  * For any TCP or UDP packet on port 5353 coming from vmbr0, forward to 10.15.0.3 on port 53
## PORT_FORWARD_RULES=(vmbr0:tcp:2222:10.15.0.2:22 vmbr0:any:5353:10.15.0.3:53)

PORT_FORWARD_RULES=(${PORT_FORWARD_RULES[@]})

### Apply all the rules:
purge_port_forward_rules
apply_port_forward_rules
EOF
    chmod a+x "${IPTABLES_RULES_SCRIPT}"
    echo "Wrote ${IPTABLES_RULES_SCRIPT}"
}

print_port_forward_rule() {
    IFS=':' read -ra rule_parts <<< "$@"
    local INTERFACE PROTOCOL IN_PORT DEST_IP DEST_PORT
    INTERFACE="${rule_parts[0]}"
    PROTOCOL="${rule_parts[1]}"
    IN_PORT="${rule_parts[2]}"
    DEST_IP="${rule_parts[3]}"
    DEST_PORT="${rule_parts[4]}"
    check_var INTERFACE PROTOCOL IN_PORT DEST_IP DEST_PORT
    echo "${INTERFACE} ${PROTOCOL} ${IN_PORT} ${DEST_IP} ${DEST_PORT}"
}

print_port_forward_rules() {
    readarray -t PORT_FORWARD_RULES < <(get_port_forward_rules)
    if [[ "${#PORT_FORWARD_RULES[@]}" -le 1 ]] && [[ "${PORT_FORWARD_RULES[0]}" == "" ]]; then
        echo "No inbound port forwarding (DNAT) rules have been created yet."
    else
        echo "## Existing inbound port forwarding (DNAT) rules:"
        (
            echo "INTERFACE PROTOCOL IN_PORT DEST_IP DEST_PORT"
            for rule in "${PORT_FORWARD_RULES[@]}"; do
                print_port_forward_rule "${rule}"
            done
        ) | column -t
    fi
}

define_port_forwarding_rules() {
    readarray -t PORT_FORWARD_RULES < <(get_port_forward_rules)
    while true; do
        confirm no "Would you like to define new port forwarding rules" "?" || break
        ask "Enter the inbound interface" INTERFACE vmbr0
        ask "Enter the protocol (tcp, udp, any)" PROTOCOL tcp
        ask "Enter the inbound Port number" IN_PORT
        check_num IN_PORT
        ask "Enter the destination IP address" DEST_IP
        validate_ip_address "${DEST_IP}" || fault "Invalid ip address: ${DEST_IP}"
        ask "Enter the destination Port number" DEST_PORT
        check_num DEST_PORT
        check_var INTERFACE PROTOCOL IN_PORT DEST_IP DEST_PORT
        local RULE="${INTERFACE}:${PROTOCOL}:${IN_PORT}:${DEST_IP}:${DEST_PORT}"
        (
            echo "INTERFACE PROTOCOL IN_PORT DEST_IP DEST_PORT"
            print_port_forward_rule "${RULE}"
        ) | column -t
        confirm yes "Is this rule correct" "?" || return
        PORT_FORWARD_RULES+=("$RULE")
    done
    create_iptables_rules "${PORT_FORWARD_RULES[@]}"
    activate_iptables_rules
    echo
    print_port_forward_rules
    echo
}

main() {
    new_interface || true
    echo
    print_port_forward_rules
    echo
    define_port_forwarding_rules
}

main
