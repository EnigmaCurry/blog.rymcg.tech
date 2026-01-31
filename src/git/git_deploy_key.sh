#!/bin/bash

######################################################
#           Git Deploy Key Manager                   #
#  Attach deploy-key identity to a git repository   #
######################################################

set -eo pipefail

stderr(){ echo "$@" >/dev/stderr; }
error(){ stderr "Error: $@"; }
fault(){ test -n "$1" && error "$1"; stderr "Exiting."; exit 1; }
check_var() {
    local missing=()
    for varname in "$@"; do
        if [[ -z "${!varname}" ]]; then
            missing+=("$varname")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        __help
        echo ""
        echo "## Error: Missing:"
        for var in "${missing[@]}"; do
            echo "   - $var"
        done
        echo ""
        exit 1
    fi
}
check_deps(){
    local missing=""
    for dep in "$@"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing="${missing} ${dep}"
        fi
    done
    if [[ -n "$missing" ]]; then fault "Missing dependencies:${missing}"; fi
}

# Parse a git remote URL and extract components
# Supports: git@host:user/repo.git, ssh://git@host/user/repo.git, https://host/user/repo.git
__parse_remote_url() {
    local url="$1"
    local -n _host=$2
    local -n _path=$3

    # Remove trailing .git if present
    url="${url%.git}"

    if [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
        # git@host:user/repo format
        _host="${BASH_REMATCH[1]}"
        _path="${BASH_REMATCH[2]}"
    elif [[ "$url" =~ ^ssh://([^@]+@)?([^/]+)/(.+)$ ]]; then
        # ssh://[user@]host/path format
        _host="${BASH_REMATCH[2]}"
        _path="${BASH_REMATCH[3]}"
    elif [[ "$url" =~ ^https?://([^/]+)/(.+)$ ]]; then
        # https://host/path format
        _host="${BASH_REMATCH[1]}"
        _path="${BASH_REMATCH[2]}"
    else
        return 1
    fi
}

# Generate a safe filename from repo path
__safe_key_name() {
    local host="$1"
    local path="$2"
    # Replace slashes and special chars with underscores
    echo "${host}__${path}" | tr '/:@' '_' | tr -s '_'
}

# Get the SSH config file path
__ssh_config_file() {
    echo "${HOME}/.ssh/config"
}

# Get the SSH keys directory
__ssh_keys_dir() {
    local dir="${HOME}/.ssh/deploy-keys"
    mkdir -p "$dir"
    chmod 700 "$dir"
    echo "$dir"
}

# Check if SSH host alias exists in config
__host_alias_exists() {
    local alias="$1"
    local config_file
    config_file=$(__ssh_config_file)

    if [[ -f "$config_file" ]]; then
        grep -q "^Host ${alias}$" "$config_file" 2>/dev/null
    else
        return 1
    fi
}

# Add SSH host alias to config
__add_host_alias() {
    local alias="$1"
    local real_host="$2"
    local key_file="$3"
    local config_file
    config_file=$(__ssh_config_file)

    mkdir -p "$(dirname "$config_file")"

    # Add newline if file exists and doesn't end with one
    if [[ -f "$config_file" ]] && [[ -s "$config_file" ]]; then
        if [[ $(tail -c1 "$config_file" | wc -l) -eq 0 ]]; then
            echo "" >> "$config_file"
        fi
        echo "" >> "$config_file"
    fi

    cat >> "$config_file" <<EOF
Host ${alias}
    HostName ${real_host}
    User git
    IdentityFile ${key_file}
    IdentitiesOnly yes
EOF

    chmod 600 "$config_file"
    stderr "## Added SSH host alias '${alias}' to ${config_file}"
}

# Update SSH host alias in config
__update_host_alias() {
    local alias="$1"
    local real_host="$2"
    local key_file="$3"
    local config_file
    config_file=$(__ssh_config_file)

    # Remove existing entry
    __remove_host_alias "$alias"

    # Add new entry
    __add_host_alias "$alias" "$real_host" "$key_file"
}

# Remove SSH host alias from config
__remove_host_alias() {
    local alias="$1"
    local config_file
    config_file=$(__ssh_config_file)

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    # Remove the Host block (from "Host alias" to next "Host " or EOF)
    local tmp_file
    tmp_file=$(mktemp)
    awk -v alias="$alias" '
        BEGIN { skip=0 }
        /^Host / {
            if ($2 == alias) {
                skip=1
                next
            } else {
                skip=0
            }
        }
        !skip { print }
    ' "$config_file" > "$tmp_file"

    mv "$tmp_file" "$config_file"
    chmod 600 "$config_file"
}

# Generate SSH host alias name from repo
__generate_alias() {
    local host="$1"
    local path="$2"
    # Create alias like: deploy--github.com--user--repo
    echo "deploy--${host}--${path}" | tr '/' '-' | tr -s '-'
}

# Get key file path for a repo
__key_file_path() {
    local alias="$1"
    local keys_dir
    keys_dir=$(__ssh_keys_dir)
    echo "${keys_dir}/${alias}"
}

# Generate a new deploy key
__generate_key() {
    local key_file="$1"
    local comment="$2"

    ssh-keygen -t ed25519 -f "$key_file" -N "" -C "$comment" >/dev/null 2>&1
    chmod 600 "$key_file"
    chmod 644 "${key_file}.pub"
    stderr "## Generated new deploy key: ${key_file}"
}

# Test if the deploy key works
__test_key() {
    local alias="$1"
    local timeout="${2:-10}"

    stderr "## Testing SSH connection to ${alias}..."
    if timeout "$timeout" ssh -T -o StrictHostKeyChecking=accept-new -o BatchMode=yes "$alias" 2>&1 | grep -qi "success\|authenticated\|welcome\|hi "; then
        stderr "## Key authentication successful!"
        return 0
    else
        # Many git servers return non-zero even on successful auth
        # Check if we at least got a response
        local result
        result=$(timeout "$timeout" ssh -T -o StrictHostKeyChecking=accept-new -o BatchMode=yes "$alias" 2>&1 || true)
        if echo "$result" | grep -qi "success\|authenticated\|welcome\|hi \|logged in"; then
            stderr "## Key authentication successful!"
            return 0
        elif echo "$result" | grep -qi "permission denied\|publickey"; then
            stderr "## Key authentication failed (permission denied)"
            return 1
        else
            # Got some response, might be okay
            stderr "## Connection established (authentication status unclear)"
            stderr "## Response: ${result}"
            return 0
        fi
    fi
}

# Convert a remote URL to use the deploy key alias
__convert_remote_url() {
    local url="$1"
    local alias="$2"
    local host path

    if ! __parse_remote_url "$url" host path; then
        fault "Cannot parse remote URL: $url"
    fi

    # Return in git@alias:path format
    echo "git@${alias}:${path}.git"
}

# Check if URL is already using a deploy key alias
__is_deploy_alias_url() {
    local url="$1"
    # Check if the host part starts with "deploy-" or "deploy--"
    if [[ "$url" =~ ^git@deploy-[^:]+: ]]; then
        return 0
    fi
    return 1
}

# Extract the existing alias from a deploy-key URL
__extract_alias_from_url() {
    local url="$1"
    if [[ "$url" =~ ^git@([^:]+): ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Main deploy-key setup function
__setup_deploy_key() {
    local remote_name="${1:-origin}"
    local no_test="${2:-}"
    local force="${3:-}"

    # Verify we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        fault "Not a git repository"
    fi

    # Get the remote URL
    local remote_url
    remote_url=$(git remote get-url "$remote_name" 2>/dev/null) || fault "Remote '${remote_name}' not found"

    stderr "## Remote URL: ${remote_url}"

    # Check if already using a deploy key alias
    if __is_deploy_alias_url "$remote_url"; then
        local existing_alias
        existing_alias=$(__extract_alias_from_url "$remote_url")
        local key_file
        key_file=$(__key_file_path "$existing_alias")

        stderr "## Already configured with deploy key alias: ${existing_alias}"

        if [[ -f "$key_file" ]]; then
            stderr "## Key file: ${key_file}"

            # Test if requested
            if [[ "$no_test" != "yes" ]]; then
                if __test_key "$existing_alias"; then
                    stderr "## Deploy key is working!"
                else
                    stderr "## Deploy key test failed. Public key:"
                    echo ""
                    cat "${key_file}.pub"
                    echo ""
                fi
            fi
        else
            stderr "## Warning: Key file not found: ${key_file}"
        fi

        # Output the alias
        echo "$existing_alias"
        return 0
    fi

    # Parse the remote URL
    local host path
    if ! __parse_remote_url "$remote_url" host path; then
        fault "Cannot parse remote URL: ${remote_url}"
    fi

    stderr "## Host: ${host}"
    stderr "## Path: ${path}"

    # Generate alias and key file path
    local alias
    alias=$(__generate_alias "$host" "$path")
    local key_file
    key_file=$(__key_file_path "$alias")

    stderr "## SSH alias: ${alias}"
    stderr "## Key file: ${key_file}"

    local key_existed=false
    local key_created=false

    # Check if key already exists
    if [[ -f "$key_file" ]]; then
        key_existed=true
        stderr "## Deploy key already exists: ${key_file}"

        if [[ "$force" == "yes" ]]; then
            stderr "## Force flag set, regenerating key..."
            rm -f "$key_file" "${key_file}.pub"
            __generate_key "$key_file" "deploy-key on ${HOSTNAME} ${host}:${path}"
            key_created=true
        fi
    else
        __generate_key "$key_file" "deploy-key on ${HOSTNAME} ${host}:${path}"
        key_created=true
    fi

    # Setup or update SSH host alias
    if __host_alias_exists "$alias"; then
        if [[ "$key_created" == "true" ]] || [[ "$force" == "yes" ]]; then
            __update_host_alias "$alias" "$host" "$key_file"
        else
            stderr "## SSH host alias '${alias}' already configured"
        fi
    else
        __add_host_alias "$alias" "$host" "$key_file"
    fi

    # Update the git remote to use the alias
    local new_url
    new_url=$(__convert_remote_url "$remote_url" "$alias")

    if [[ "$remote_url" != "$new_url" ]]; then
        git remote set-url "$remote_name" "$new_url"
        stderr "## Updated remote '${remote_name}' URL to: ${new_url}"
    else
        stderr "## Remote '${remote_name}' already using deploy-key alias"
    fi

    # Print public key if newly created
    if [[ "$key_created" == "true" ]]; then
        echo ""
        echo "========================================"
        echo "NEW DEPLOY KEY CREATED"
        echo "========================================"
        echo ""
        echo "Add this public key as a deploy key on your git server:"
        echo ""
        cat "${key_file}.pub"
        echo ""
        echo "========================================"
        echo ""
        echo "For GitHub: Settings → Deploy keys → Add deploy key"
        echo "For GitLab: Settings → Repository → Deploy keys"
        echo "For Forgejo/Gitea: Settings → Deploy Keys → Add Deploy Key"
        echo ""
    elif [[ "$key_existed" == "true" ]] && [[ "$no_test" != "yes" ]]; then
        # Test existing key
        echo ""
        if __test_key "$alias"; then
            echo "## Deploy key is working!"
        else
            echo ""
            echo "## Deploy key test failed. You may need to add/re-add the key."
            echo "## Public key:"
            echo ""
            cat "${key_file}.pub"
            echo ""
        fi
    fi

    # Output the alias for use by other scripts
    echo "$alias"
}

# Show current deploy-key configuration
__show_config() {
    local remote_name="${1:-origin}"

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        fault "Not a git repository"
    fi

    local remote_url
    remote_url=$(git remote get-url "$remote_name" 2>/dev/null) || fault "Remote '${remote_name}' not found"

    echo "Remote: ${remote_name}"
    echo "URL: ${remote_url}"

    # Check if using deploy key alias
    if [[ "$remote_url" =~ ^git@deploy-- ]]; then
        local alias
        alias=$(echo "$remote_url" | sed 's/^git@\([^:]*\):.*/\1/')
        local key_file
        key_file=$(__key_file_path "$alias")

        echo "Deploy alias: ${alias}"
        echo "Key file: ${key_file}"

        if [[ -f "$key_file" ]]; then
            echo "Key exists: yes"
            echo "Public key:"
            cat "${key_file}.pub"
        else
            echo "Key exists: no (KEY MISSING!)"
        fi
    else
        echo "Deploy key: not configured (using default SSH identity)"
    fi
}

__help() {
    local script
    script=$(basename "$0")
    cat <<EOF
## git deploy-key - Attach deploy-key identity to a git repository

Usage: ${script} [options]

Options:
    --remote <name>    Remote name to configure (default: origin)
    --no-test          Skip testing the key after setup
    --force            Regenerate key even if it exists
    --show             Show current deploy-key configuration
    -h, --help         Show this help message

Description:
    This command attaches a deploy-key identity to an existing local Git
    repository by:

    1. Creating (or reusing) a repository-specific SSH key
    2. Ensuring the repo's remote uses an SSH host alias pointing to that key
    3. Optionally verifying the key works (only when the key already existed)

Examples:
    # Setup deploy key for origin remote
    git deploy-key

    # Setup deploy key for a different remote
    git deploy-key --remote upstream

    # Force regenerate the deploy key
    git deploy-key --force

    # Show current configuration
    git deploy-key --show

After running, if a new key was created, add the printed public key as a
deploy key on your git server (GitHub/GitLab/Forgejo/etc).
EOF
}

main() {
    check_deps git ssh-keygen ssh

    local remote_name="origin"
    local no_test=""
    local force=""
    local show=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --remote)
                remote_name="$2"
                shift 2
                ;;
            --no-test)
                no_test="yes"
                shift
                ;;
            --force)
                force="yes"
                shift
                ;;
            --show)
                show="yes"
                shift
                ;;
            -h|--help)
                __help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                __help
                exit 1
                ;;
        esac
    done

    if [[ "$show" == "yes" ]]; then
        __show_config "$remote_name"
    else
        __setup_deploy_key "$remote_name" "$no_test" "$force"
    fi
}

main "$@"
