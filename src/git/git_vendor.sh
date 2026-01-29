#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Default domain when not specified
DEFAULT_DOMAIN="github.com"

# Parse a git repository reference into domain, org, and repo components
# Sets global variables: domain, org_name, repo_name, use_ssh, ssh_port
parse_repo_ref() {
    local input="$1"
    use_ssh=false
    ssh_port=""

    # Remove trailing slashes
    input="${input%/}"

    # https://domain/org/repo or https://domain/org/repo.git
    if [[ "$input" =~ ^https?://([^/]+)/([^/]+)/([^/]+)/?$ ]]; then
        domain="${BASH_REMATCH[1]}"
        org_name="${BASH_REMATCH[2]}"
        repo_name="${BASH_REMATCH[3]}"

    # ssh://[git@]domain[:port]/org/repo or ssh://[git@]domain[:port]/org/repo.git
    elif [[ "$input" =~ ^ssh://(git@)?([^/:]+)(:([0-9]+))?/([^/]+)/(.+)$ ]]; then
        domain="${BASH_REMATCH[2]}"
        ssh_port="${BASH_REMATCH[4]}"
        org_name="${BASH_REMATCH[5]}"
        repo_name="${BASH_REMATCH[6]}"
        use_ssh=true

    # git@domain:org/repo.git or git@domain:org/repo
    elif [[ "$input" =~ ^git@([^:]+):([^/]+)/(.+)$ ]]; then
        domain="${BASH_REMATCH[1]}"
        org_name="${BASH_REMATCH[2]}"
        repo_name="${BASH_REMATCH[3]}"
        use_ssh=true

    # domain/org/repo (three path components with dots in first)
    elif [[ "$input" =~ ^([a-zA-Z0-9.-]+\.[a-zA-Z]+)/([^/]+)/([^/]+)$ ]]; then
        domain="${BASH_REMATCH[1]}"
        org_name="${BASH_REMATCH[2]}"
        repo_name="${BASH_REMATCH[3]}"

    # org/repo (two components, assume default domain)
    elif [[ "$input" =~ ^([^/]+)/([^/]+)$ ]]; then
        domain="$DEFAULT_DOMAIN"
        org_name="${BASH_REMATCH[1]}"
        repo_name="${BASH_REMATCH[2]}"

    else
        echo "Invalid repository format: $input" >&2
        echo "Supported formats:" >&2
        echo "  org/repo" >&2
        echo "  github.com/org/repo" >&2
        echo "  https://github.com/org/repo" >&2
        echo "  ssh://git@github.com/org/repo" >&2
        echo "  ssh://git@github.com:22/org/repo" >&2
        echo "  git@github.com:org/repo.git" >&2
        exit 1
    fi

    # Normalize: remove .git suffix from repo name
    repo_name="${repo_name%.git}"

    # Normalize: lowercase the org name for consistent directory structure
    org_name="${org_name,,}"
}

# Build the clone URL from parsed components
build_clone_url() {
    if [[ "$use_ssh" == true ]]; then
        if [[ -n "$ssh_port" ]]; then
            echo "ssh://git@$domain:$ssh_port/$org_name/$repo_name.git"
        else
            echo "git@$domain:$org_name/$repo_name.git"
        fi
    else
        echo "https://$domain/$org_name/$repo_name"
    fi
}

# Check if the user provided a URL
if [ "$#" -lt 1 ]; then
    echo "Usage: git vendor <repository>"
    echo ""
    echo "Examples:"
    echo "  git vendor enigmacurry/sway-home"
    echo "  git vendor github.com/enigmacurry/sway-home"
    echo "  git vendor https://github.com/EnigmaCurry/sway-home.git"
    echo "  git vendor git@github.com:EnigmaCurry/sway-home.git"
    echo "  git vendor ssh://git@github.com:22/EnigmaCurry/sway-home.git"
    exit 1
fi

# Parse the input
parse_repo_ref "$1"

# Build the clone URL
clone_url=$(build_clone_url)

# Define the target directory
vendor_dir="$HOME/git/vendor"
target_dir="$vendor_dir/$org_name/$repo_name"

# Check if already cloned
if [ -d "$target_dir" ]; then
    echo "Repository already exists at $target_dir"
    exit 0
fi

# Ensure the parent directory exists
mkdir -p "$vendor_dir/$org_name"

# Clone the repository
echo "Cloning $clone_url to $target_dir"
git clone "$clone_url" "$target_dir"

echo "Repository cloned to $target_dir"
