#!/bin/bash
## Reset and configure the Proxmox firewall.

set -eo pipefail
stderr(){ echo "$@" >/dev/stderr; }
error(){ stderr "Error: $@"; }
cancel(){ stderr "Canceled."; exit 2; }
fault(){ test -n "$1" && error $1; stderr "Exiting."; exit 1; }
confirm() {
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
validate_ip_address () {
    #thanks https://stackoverflow.com/a/21961938
    echo "$@" | grep -o -E  '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)' >/dev/null
}

add_management_rule_macro() {
    MACRO=$1
    check_var HOSTNAME MACRO MANAGER_INTERFACE MANAGER_SUBNET PUBLIC_IP_ADDRESS
    pvesh create /nodes/${HOSTNAME}/firewall/rules \
          --action ACCEPT --type in --macro ${MACRO} \
          --iface ${MANAGER_INTERFACE} --source ${MANAGER_SUBNET} --dest ${PUBLIC_IP_ADDRESS} --enable 1 \
          --comment "Allow ${MACRO^^} from ${MANAGER_SUBNET} on ${MANAGER_INTERFACE} for ${PUBLIC_IP_ADDRESS}"
}

add_management_rule_port() {
    PORT=$1
    check_var HOSTNAME MANAGER_INTERFACE MANAGER_SUBNET PUBLIC_IP_ADDRESS
    check_num PORT
    pvesh create /nodes/${HOSTNAME}/firewall/rules \
          --action ACCEPT --type in --dport ${PORT} --proto tcp \
          --iface ${MANAGER_INTERFACE} --source ${MANAGER_SUBNET} --dest ${PUBLIC_IP_ADDRESS} --enable 1 \
          --comment "Allow from ${MANAGER_SUBNET} on ${MANAGER_INTERFACE} to ${PUBLIC_IP_ADDRESS}:${PORT}"
}


reset_firewall() {
    confirm no "This will reset the Node and Datacenter firewalls and delete all existing rules."
    echo
    ask "Enter the management interface (e.g., vmbr0)" MANAGER_INTERFACE vmbr0
    ask "Which subnet is allowed to access the management interface?" MANAGER_SUBNET 0.0.0.0/0
    echo
    PUBLIC_IP_ADDRESS=$(ip -4 addr show ${MANAGER_INTERFACE} | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    validate_ip_address ${PUBLIC_IP_ADDRESS}
    
    ## Delete existing Datacenter rules
    RULE_POSITIONS="$(pvesh get /cluster/firewall/rules --output-format json | jq -r '.[].pos' | sort -r)"
    # Iterate over each rule position and delete the rule
    for POS in ${RULE_POSITIONS}; do
        echo "Deleting cluster firewall rule at position ${POS}."
        pvesh delete "/cluster/firewall/rules/${POS}"
    done

    ## Delete existing Node rules
    RULE_POSITIONS="$(pvesh get /nodes/${HOSTNAME}/firewall/rules --output-format json | jq -r '.[].pos' | sort -r)"
    # Iterate over each rule position and delete the rule
    for POS in ${RULE_POSITIONS}; do
        echo "Deleting node firewall rule at position ${POS}."
        pvesh delete "/nodes/${HOSTNAME}/firewall/rules/${POS}"
    done

    echo "Allowing ICMP ping response from the management interface."
    add_management_rule_macro ping
    echo "Allowing access to SSH (22) for the management interface."
    add_management_rule_macro ssh
    echo "Allowing access to Proxmox console (8006) for the management interface."
    add_management_rule_port 8006
    
    echo "Enabling Node firewall."
    pvesh set /nodes/${HOSTNAME}/firewall/options --enable 1

    echo "Enabling Datacenter firewall."
    pvesh set /cluster/firewall/options --policy_in DROP --policy_out ACCEPT
    pvesh set /cluster/firewall/options --enable 1
}

reset_firewall
