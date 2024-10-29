#!/bin/bash
## Reset and configure the Proxmox firewall.

MANAGER_INTERFACE=${MANAGER_INTERFACE:-vmbr0}

set -eo pipefail
stderr(){ echo "$@" >/dev/stderr; }
error(){ stderr "Error: $@"; }
cancel(){ stderr "Canceled."; exit 2; }
fault(){ test -n "$1" && error $1; stderr "Exiting."; exit 1; }
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
debug_var() {
    local var=$1
    check_var var
    echo "## DEBUG: ${var}=${!var}" > /dev/stderr
}


reset_firewall() {
    confirm no "This will reset the Node and Datacenter firewalls and delete all existing rules."
    echo
    ask "Which subnet is allowed to access the management interface?" MANAGER_SUBNET 0.0.0.0/0
    echo
    PUBLIC_IP_ADDRESS=$(ip -4 addr show ${MANAGER_INTERFACE} | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

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
    pvesh create /nodes/${HOSTNAME}/firewall/rules \
          --action ACCEPT --type in --macro ping \
          --iface ${MANAGER_INTERFACE} --source ${MANAGER_SUBNET} --dest ${PUBLIC_IP_ADDRESS} --enable 1 \
          --comment "Allow ICMP ping from ${MANAGER_SUBNET} on ${MANAGER_INTERFACE} for ${PUBLIC_IP_ADDRESS}"

    echo "Allowing access to SSH (22) for the management interface."
    pvesh create /nodes/${HOSTNAME}/firewall/rules \
          --action ACCEPT --type in --macro ssh \
          --iface ${MANAGER_INTERFACE} --source ${MANAGER_SUBNET} --dest ${PUBLIC_IP_ADDRESS} --enable 1 \
          --comment "Allow SSH from ${MANAGER_SUBNET} on ${MANAGER_INTERFACE} for ${PUBLIC_IP_ADDRESS}"

    echo "Allowing access to Proxmox console (8006) for the management interface."
    pvesh create /nodes/${HOSTNAME}/firewall/rules \
          --action ACCEPT --type in --dport 8006 --proto tcp \
          --iface ${MANAGER_INTERFACE} --source ${MANAGER_SUBNET} --dest ${PUBLIC_IP_ADDRESS} --enable 1 \
          --comment "Allow Proxmox Web Console from ${MANAGER_SUBNET} on ${MANAGER_INTERFACE} for ${PUBLIC_IP_ADDRESS}"

    echo "Enabling Node firewall."
    pvesh set /nodes/${HOSTNAME}/firewall/options --enable 1

    echo "Enabling Datacenter firewall."
    pvesh set /cluster/firewall/options --policy_in DROP --policy_out ACCEPT
    pvesh set /cluster/firewall/options --enable 1
}

reset_firewall
