#!/bin/bash

######################################################
#     Git Deploy - Clone with Deploy Key Auth       #
######################################################

set -eo pipefail

ORIGINAL_ARGS="${@}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

#-----------------------------------------------------------
# URL Parsing
#-----------------------------------------------------------

# Parse repository URL with optional branch
# Format: url[#branch]
# Returns: Sets REPO_URL and REPO_BRANCH variables
__parse_repo_spec() {
    local spec="$1"

    if [[ "$spec" =~ ^(.+)#([^#]+)$ ]]; then
        REPO_URL="${BASH_REMATCH[1]}"
        REPO_BRANCH="${BASH_REMATCH[2]}"
    else
        REPO_URL="$spec"
        REPO_BRANCH=""
    fi
}

# Parse a git remote URL and extract host and path components
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

# Extract repository name from URL for default destination
__repo_name_from_url() {
    local url="$1"
    local name

    # Remove trailing .git
    url="${url%.git}"

    # Extract last path component
    name="${url##*/}"

    # Handle ssh format (git@host:user/repo)
    if [[ "$name" == *:* ]]; then
        name="${name##*:}"
        name="${name##*/}"
    fi

    echo "$name"
}

# Normalize URL to SSH format for consistency
__normalize_url() {
    local url="$1"

    # Remove trailing .git if present, we'll add it back
    url="${url%.git}"

    # Convert HTTPS to SSH format
    if [[ "$url" =~ ^https?://([^/]+)/(.+)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local path="${BASH_REMATCH[2]}"
        echo "git@${host}:${path}.git"
    elif [[ "$url" =~ ^git@ ]]; then
        # Already SSH format
        echo "${url}.git"
    elif [[ "$url" =~ ^ssh:// ]]; then
        # ssh:// format, convert to git@ format
        local rest="${url#ssh://}"
        rest="${rest#*@}"  # Remove user@ if present
        if [[ "$rest" =~ ^([^/]+)/(.+)$ ]]; then
            echo "git@${BASH_REMATCH[1]}:${BASH_REMATCH[2]}.git"
        else
            echo "${url}.git"
        fi
    else
        # Unknown format, return as-is with .git
        echo "${url}.git"
    fi
}

# Check if URL is already using a deploy key alias
__is_deploy_alias_url() {
    local url="$1"
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

#-----------------------------------------------------------
# SSH Key Management
#-----------------------------------------------------------

__ssh_config_file() {
    echo "${HOME}/.ssh/config"
}

__ssh_keys_dir() {
    local dir="${HOME}/.ssh/deploy-keys"
    mkdir -p "$dir"
    chmod 700 "$dir"
    echo "$dir"
}

# Generate SSH host alias name from repo
__generate_alias() {
    local host="$1"
    local path="$2"
    echo "deploy--${host}--${path}" | tr '/' '-' | tr -s '-'
}

# Get key file path for an alias
__key_file_path() {
    local alias="$1"
    local keys_dir
    keys_dir=$(__ssh_keys_dir)
    echo "${keys_dir}/${alias}"
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
    stderr "## Added SSH host alias '${alias}'"
}

# Remove SSH host alias from config
__remove_host_alias() {
    local alias="$1"
    local config_file
    config_file=$(__ssh_config_file)

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

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

# Update SSH host alias in config
__update_host_alias() {
    local alias="$1"
    local real_host="$2"
    local key_file="$3"

    __remove_host_alias "$alias"
    __add_host_alias "$alias" "$real_host" "$key_file"
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

#-----------------------------------------------------------
# Deploy Key Setup
#-----------------------------------------------------------

# Setup deploy key for a remote - returns the alias name
# Sets KEY_FILE and KEY_CREATED variables
__setup_deploy_key() {
    local remote_name="${1:-origin}"

    local remote_url
    remote_url=$(git remote get-url "$remote_name" 2>/dev/null) || fault "Remote '${remote_name}' not found"

    # Check if already using a deploy key alias
    if __is_deploy_alias_url "$remote_url"; then
        local existing_alias
        existing_alias=$(__extract_alias_from_url "$remote_url")
        KEY_FILE=$(__key_file_path "$existing_alias")
        KEY_CREATED=false

        stderr "## Already configured with deploy key: ${existing_alias}"
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
    KEY_FILE=$(__key_file_path "$alias")

    stderr "## SSH alias: ${alias}"
    stderr "## Key file: ${KEY_FILE}"

    KEY_CREATED=false

    # Check if key already exists
    if [[ -f "$KEY_FILE" ]]; then
        stderr "## Deploy key already exists"
    else
        __generate_key "$KEY_FILE" "deploy-key@${HOSTNAME:-localhost} ${host}:${path}"
        KEY_CREATED=true
    fi

    # Setup or update SSH host alias
    if __host_alias_exists "$alias"; then
        stderr "## SSH host alias already configured"
    else
        __add_host_alias "$alias" "$host" "$KEY_FILE"
    fi

    # Update the git remote to use the alias
    local new_url
    new_url=$(__convert_remote_url "$remote_url" "$alias")

    if [[ "$remote_url" != "$new_url" ]]; then
        git remote set-url "$remote_name" "$new_url"
        stderr "## Updated remote URL to use deploy key"
    fi

    echo "$alias"
}

#-----------------------------------------------------------
# Repository Setup
#-----------------------------------------------------------

# Initialize the repository and configure remote
__init_repo() {
    local dest="$1"
    local url="$2"
    local remote_name="${3:-origin}"

    # Create destination directory
    if [[ -d "$dest" ]]; then
        if [[ -d "${dest}/.git" ]]; then
            stderr "## Directory already contains a git repository: ${dest}"
            stderr "## Updating configuration..."
        else
            fault "Directory exists but is not a git repository: ${dest}"
        fi
    else
        mkdir -p "$dest"
        stderr "## Created directory: ${dest}"
    fi

    cd "$dest"

    # Initialize if not already a git repo
    if [[ ! -d ".git" ]]; then
        git init --quiet
        stderr "## Initialized empty git repository"

        # Point HEAD to a placeholder branch
        git symbolic-ref HEAD refs/heads/__deploy_pending__
    fi

    # Configure remote
    if git remote get-url "$remote_name" >/dev/null 2>&1; then
        git remote set-url "$remote_name" "$url"
        stderr "## Updated remote '${remote_name}': ${url}"
    else
        git remote add "$remote_name" "$url"
        stderr "## Added remote '${remote_name}': ${url}"
    fi

    # Set default remote for convenience
    git config checkout.defaultRemote "$remote_name"
}

# Test if the deploy key works by trying to access the remote
__test_deploy_key() {
    local remote_name="$1"
    local timeout_secs="${2:-10}"

    if timeout "$timeout_secs" git ls-remote --heads "$remote_name" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Get the default branch from the remote
__get_default_branch() {
    local remote_name="$1"

    local default_ref
    default_ref=$(git ls-remote --symref "$remote_name" HEAD 2>/dev/null | grep "^ref:" | awk '{print $2}' | sed 's|refs/heads/||')

    if [[ -n "$default_ref" ]]; then
        echo "$default_ref"
        return 0
    fi

    # Fallback: check common branch names
    local branches
    branches=$(git ls-remote --heads "$remote_name" 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||')

    for try_branch in main master develop; do
        if echo "$branches" | grep -q "^${try_branch}$"; then
            echo "$try_branch"
            return 0
        fi
    done

    echo "$branches" | head -1
}

# Show the public key and instructions
__show_key_instructions() {
    local key_file="$1"

    echo ""
    echo "========================================"
    echo "DEPLOY KEY NOT YET AUTHORIZED"
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
}

#-----------------------------------------------------------
# Main
#-----------------------------------------------------------

__help() {
    local script
    script=$(basename "$0")
    cat <<EOF
## git deploy - Clone a repository using a deploy key

Usage: ${script} <repo-url[#branch]> [destination] [options]

Arguments:
    repo-url        Repository URL (supports #branch suffix)
    destination     Local directory (default: derived from repo name)

Options:
    --remote <name>    Remote name (default: origin)
    --branch <name>    Branch to clone (overrides #branch in URL)
    -h, --help         Show this help message

Description:
    Clones a repository using a dedicated deploy key for authentication.

    If the deploy key is already authorized:
    - Discovers the default branch automatically (if not specified)
    - Fetches and checks out the repository
    - Exits successfully (code 0)

    If the deploy key is NOT yet authorized:
    - Creates the deploy key and shows the public key
    - Prints instructions to add it to your git server
    - Exits with error code 1 (re-run after adding the key)

URL Formats:
    git@github.com:user/repo.git
    git@github.com:user/repo.git#main
    https://github.com/user/repo
    https://github.com/user/repo#develop

Examples:
    # Clone using remote's default branch
    git deploy git@github.com:user/repo.git

    # Clone specific branch
    git deploy git@github.com:user/repo.git#develop

    # Clone to specific directory
    git deploy git@github.com:user/repo.git ~/projects/myrepo

Workflow:
    1. Run 'git deploy <url>'
    2. If key not yet authorized, add the printed key to your git server
    3. Re-run 'git deploy <url>' - repository will be cloned
EOF
}

main() {
    check_deps git ssh-keygen

    local repo_spec=""
    local destination=""
    local remote_name="origin"
    local branch_override=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --remote)
                remote_name="$2"
                shift 2
                ;;
            --branch)
                branch_override="$2"
                shift 2
                ;;
            -h|--help)
                __help
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                __help
                exit 1
                ;;
            *)
                if [[ -z "$repo_spec" ]]; then
                    repo_spec="$1"
                elif [[ -z "$destination" ]]; then
                    destination="$1"
                else
                    error "Too many arguments"
                    __help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    check_var repo_spec

    # Parse repo spec
    __parse_repo_spec "$repo_spec"

    # Apply branch override if specified
    if [[ -n "$branch_override" ]]; then
        REPO_BRANCH="$branch_override"
    fi

    # Normalize URL to SSH format
    REPO_URL=$(__normalize_url "$REPO_URL")

    # Derive destination from repo name if not specified
    if [[ -z "$destination" ]]; then
        destination=$(__repo_name_from_url "$REPO_URL")
    fi

    # Convert to absolute path
    if [[ "$destination" != /* ]]; then
        destination="$(pwd)/${destination}"
    fi

    stderr "## Repository URL: ${REPO_URL}"
    stderr "## Destination: ${destination}"
    [[ -n "$REPO_BRANCH" ]] && stderr "## Branch: ${REPO_BRANCH}"
    stderr ""

    # Initialize the repository
    __init_repo "$destination" "$REPO_URL" "$remote_name"

    # Setup deploy key
    stderr ""
    stderr "## Setting up deploy key..."
    KEY_FILE=""
    KEY_CREATED=false
    __setup_deploy_key "$remote_name" >/dev/null

    # Test deploy key
    stderr ""
    stderr "## Testing deploy key..."

    if __test_deploy_key "$remote_name"; then
        stderr "## Deploy key is working!"

        # If no branch specified, discover the default branch
        if [[ -z "$REPO_BRANCH" ]]; then
            stderr "## Discovering default branch..."
            REPO_BRANCH=$(__get_default_branch "$remote_name")
            if [[ -n "$REPO_BRANCH" ]]; then
                stderr "## Default branch: ${REPO_BRANCH}"
            else
                fault "Could not determine default branch from remote"
            fi
        fi

        # Fetch from remote
        stderr "## Fetching from ${remote_name}..."
        git fetch "$remote_name"

        # Checkout the branch
        stderr "## Checking out branch '${REPO_BRANCH}'..."
        git checkout "$REPO_BRANCH"

        # Ensure tracking is configured
        git branch --set-upstream-to="${remote_name}/${REPO_BRANCH}" "$REPO_BRANCH" 2>/dev/null || true

        stderr ""
        stderr "========================================"
        stderr "## Repository cloned successfully!"
        stderr "## Location: ${destination}"
        stderr "## Branch: ${REPO_BRANCH}"
        stderr "========================================"
    else
        # Key not working - show instructions and exit with error
        if [[ -n "$KEY_FILE" ]] && [[ -f "${KEY_FILE}.pub" ]]; then
            __show_key_instructions "$KEY_FILE"
        else
            stderr ""
            stderr "## Deploy key not working and key file not found."
        fi

        stderr ""
        stderr "## Repository prepared at: ${destination}"
        stderr "## After adding the deploy key, run this command again:"
        stderr "##   git deploy ${ORIGINAL_ARGS}"
        stderr ""

        echo "$destination"
        exit 1
    fi

    echo "$destination"
}

main "$@"
