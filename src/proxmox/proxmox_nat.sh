#!/bin/bash

SYSTEMD_UNIT="my-iptables-rules"
SYSTEMD_SERVICE="/etc/systemd/system/${SYSTEMD_UNIT}.service"
IPTABLES_RULES_SCRIPT="/etc/network/${SYSTEMD_UNIT}.sh"

set -eo pipefail
stderr(){ echo "$@" >/dev/stderr; }
error(){ stderr "Error: $@"; }
cancel(){ stderr "Canceled."; exit 2; }
fault(){ test -n "$1" && error $1; stderr "Exiting."; exit 1; }
print_array(){ printf '%s\n' "$@"; }
trim_trailing_whitespace() { sed -e 's/[[:space:]]*$//'; }
trim_leading_whitespace() { sed -e 's/^[[:space:]]*//'; }
trim_whitespace() { trim_leading_whitespace | trim_trailing_whitespace; }
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
ask_allow_blank() {
    local __prompt="${1}"; local __var="${2}"; local __default="${3}"
    read -e -p "${__prompt}"$'\x0a\e[32m:\e[0m ' -i "${__default}" ${__var}
    export ${__var}
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
    (
        echo "BRIDGE|NETWORK|COMMENT
"
        for i in "${INTERFACES[@]}"; do
            local COMMENT="$(get_interface_comment ${i})"
            echo "${i}|x.x.x.x|$(get_interface_comment ${i})"
        done
    ) | column -t -s '|' | trim_trailing_whitespace
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
    local INTERFACE IP_CIDR IP_ADDRESS NETMASK COMMENT OTHER_BRIDGE DEFAULT_IP_CIDR
    set -e
    echo
    echo "Configuring new NAT bridge ..."
    ask "Enter the existing bridge to NAT from" OTHER_BRIDGE vmbr0
    if ! element_in_array "$OTHER_BRIDGE" "${INTERFACES[@]}"; then
        fault "Sorry, ${OTHER_BRIDGE} is not a valid bridge (it does not exist)"
    fi
    ask "Enter a unique number for the new bridge (don't write the vmbr prefix)" BRIDGE_NUMBER
    check_num BRIDGE_NUMBER
    INTERFACE="vmbr${BRIDGE_NUMBER}"

    if element_in_array "$INTERFACE" "${INTERFACES[@]}"; then
        error "Sorry, ${INTERFACE} already exists."
        echo
        return
    fi
    echo
    echo "Configuring new interface: ${INTERFACE}"
    if [[ "${BRIDGE_NUMBER}" -ge 0 ]] && [[ "${BRIDGE_NUMBER}" -le 255 ]]; then
        DEFAULT_IP_CIDR="10.${BRIDGE_NUMBER}.0.1/24"
    else
        DEFAULT_IP_CIDR=""
    fi
    ask "Enter the static IP address and network prefix in CIDR notation for ${INTERFACE}:" IP_CIDR "${DEFAULT_IP_CIDR}"
    if ! validate_ip_network "${IP_CIDR}"; then
        fault "Bad IP address/network prefix (use the format eg. 192.168.1.1/24)"
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
    echo
    ask "Enter the description/comment for this interface" COMMENT "NAT ${IP_CIDR} bridged to ${OTHER_BRIDGE}"
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

get_interface_comment() {
    awk "/^iface ${1} /,/^$/" /etc/network/interfaces | grep -v -e '^$' | grep -e '^#' | tail -1 | tr -d '#'
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
##  * For any UDP packet on port 5353 coming from vmbr0, forward to 10.15.0.3 on port 53
## PORT_FORWARD_RULES=(vmbr0:tcp:2222:10.15.0.2:22 vmbr0:udp:5353:10.15.0.3:53)

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
    echo "${INTERFACE}|${PROTOCOL}|${IN_PORT}|${DEST_IP}|${DEST_PORT}"
}

print_port_forward_rules() {
    readarray -t PORT_FORWARD_RULES < <(get_port_forward_rules)
    if [[ "${#PORT_FORWARD_RULES[@]}" -le 1 ]] && [[ "${PORT_FORWARD_RULES[0]}" == "" ]]; then
        echo "No inbound port forwarding (DNAT) rules have been created yet."
    else
        echo "## Existing inbound port forwarding (DNAT) rules:"
        (
            echo "INTERFACE|PROTOCOL|IN_PORT|DEST_IP|DEST_PORT"
            for rule in "${PORT_FORWARD_RULES[@]}"; do
                print_port_forward_rule "${rule}"
            done
        ) | column -t -s '|'
    fi
}

define_port_forwarding_rules() {
    readarray -t PORT_FORWARD_RULES < <(get_port_forward_rules)
    while true; do
        echo "Defining new port forward rule:"
        ask "Enter the inbound interface" INTERFACE vmbr0
        ask "Enter the protocol (tcp, udp)" PROTOCOL tcp
        ask "Enter the inbound Port number" IN_PORT
        check_num IN_PORT
        ask "Enter the destination IP address" DEST_IP
        validate_ip_address "${DEST_IP}" || fault "Invalid ip address: ${DEST_IP}"
        ask "Enter the destination Port number" DEST_PORT
        check_num DEST_PORT
        check_var INTERFACE PROTOCOL IN_PORT DEST_IP DEST_PORT
        local RULE="${INTERFACE}:${PROTOCOL}:${IN_PORT}:${DEST_IP}:${DEST_PORT}"
        (
            echo "INTERFACE|PROTOCOL|IN_PORT|DEST_IP|DEST_PORT"
            print_port_forward_rule "${RULE}"
        ) | column -t -s '|'
        confirm yes "Is this rule correct" "?" || return
        PORT_FORWARD_RULES+=("$RULE")
        echo
        confirm no "Would you like to define more port forwarding rules now" "?" || break
    done
    create_iptables_rules "${PORT_FORWARD_RULES[@]}"
    activate_iptables_rules
    echo
    print_port_forward_rules
    echo
}

delete_port_forwarding_rules() {
    readarray -t PORT_FORWARD_RULES < <(get_port_forward_rules)
    while true; do
        if [[ "${PORT_FORWARD_RULES[@]}" == "" ]]; then
            print_port_forward_rules
            break
        fi
        echo
        (
            echo "LINE# INTERFACE PROTOCOL IN_PORT DEST_IP DEST_PORT"
            print_port_forward_rules 2>/dev/null | grep -v "#" | tail -n +2 | cat -n | trim_whitespace
        ) | column -t | trim_whitespace
        ask_allow_blank 'Enter the line number for the rule you wish to delete (type `q` or blank for none)' RULE_TO_DELETE
        if [[ -z "${RULE_TO_DELETE}" ]] || [[ "${RULE_TO_DELETE}" == "q" ]]; then
            break
        fi
        RULE_TO_DELETE=$((${RULE_TO_DELETE} - 1))
        if [[ "${RULE_TO_DELETE}" -lt 0 ]] || \
               [[ "${RULE_TO_DELETE}" -gt "${#PORT_FORWARD_RULES[@]}" ]]; then
            error "Invalid rule number"
            break
        fi
        local to_delete="${PORT_FORWARD_RULES[${RULE_TO_DELETE}]}"
        PORT_FORWARD_RULES=("${PORT_FORWARD_RULES[@]/${to_delete}}")
        create_iptables_rules "${PORT_FORWARD_RULES[@]}"
        activate_iptables_rules
    done
    echo
}

print_help() {
    echo "NAT bridge tool:"
    echo ' * Type `i` or `interfaces` to list the bridge interfaces.'
    echo ' * Type `c` or `create` to create a new NAT bridge.'
    echo ' * Type `l` or `list` to list the NAT rules.'
    echo ' * Type `n` or `new` to create some new NAT rules.'
    echo ' * Type `d` or `delete` to delete some existing NAT rules.'
    echo ' * Type `?` or `help` to see this help message again.'
    echo ' * Type `q` or `quit` to quit.'
}

main() {
    # new_interface || true
    # echo
    # print_port_forward_rules
    # echo
    # define_port_forwarding_rules
    # echo
    # delete_port_forwarding_rules

    echo
    get_bridges
    echo
    while :
    do
        print_help
        echo
        ask_allow_blank 'Enter command (for help, enter `?`)' COMMAND
        echo
        if [[ "$COMMAND" == 'q' ]] || [[ "$COMMAND" == 'quit' ]]; then
            echo "goodbye"
            exit 0
        elif [[ $COMMAND == '?' || $COMMAND == "help" ]]; then
            print_help
        elif [[ $COMMAND == "i" || $COMMAND == "interfaces" ]]; then
            get_bridges
        elif [[ $COMMAND == "c" || $COMMAND == "create" ]]; then
            get_bridges
            new_interface || true
        elif [[ $COMMAND == "l" || $COMMAND == "list" ]]; then
            print_port_forward_rules
        elif [[ $COMMAND == "n" || $COMMAND == "new" ]]; then
            define_port_forwarding_rules
        elif [[ $COMMAND == "d" || $COMMAND == "delete" ]]; then
            delete_port_forwarding_rules
        fi
        echo
    done
}

main
