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

# Initialize the repository and configure remote/branch
__init_repo() {
    local dest="$1"
    local url="$2"
    local branch="$3"
    local remote_name="${4:-origin}"

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

        # Point HEAD to a placeholder branch to prevent confusing "master has no commits" errors
        # This makes it clear the repo needs 'git fetch && git checkout <branch>'
        git symbolic-ref HEAD refs/heads/__you_need_to_run_git_fetch_and_then_checkout_a_branch__
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

# Find git-deploy-key command
__find_deploy_key_cmd() {
    # Check if git-deploy-key is in PATH
    if command -v git-deploy-key >/dev/null 2>&1; then
        echo "git-deploy-key"
        return 0
    fi
    return 1
}

# Test if the deploy key works by trying to access the remote
__test_deploy_key() {
    local remote_name="$1"
    local timeout_secs="${2:-10}"

    local remote_url
    remote_url=$(git remote get-url "$remote_name" 2>/dev/null) || return 1

    # Try git ls-remote which requires authentication
    if timeout "$timeout_secs" git ls-remote --heads "$remote_name" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Get the default branch from the remote
__get_default_branch() {
    local remote_name="$1"

    # Try to get the default branch via symbolic ref
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

    # Last resort: first branch listed
    echo "$branches" | head -1
}

# Get the deploy key file path from git config or derive it
__get_deploy_key_file() {
    local remote_name="$1"

    local remote_url
    remote_url=$(git remote get-url "$remote_name" 2>/dev/null) || return 1

    # Extract the alias from URL like git@deploy--host--path:path.git
    if [[ "$remote_url" =~ ^git@(deploy-[^:]+): ]]; then
        local alias="${BASH_REMATCH[1]}"
        local key_file="${HOME}/.ssh/deploy-keys/${alias}"
        if [[ -f "$key_file" ]]; then
            echo "$key_file"
            return 0
        fi
    fi
    return 1
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

# Configure branch tracking
__configure_branch() {
    local branch="$1"
    local remote_name="$2"

    git config deploy.branch "$branch"
    git symbolic-ref HEAD "refs/heads/${branch}"

    # Pre-configure tracking so 'git pull' works after first checkout
    git config "branch.${branch}.remote" "$remote_name"
    git config "branch.${branch}.merge" "refs/heads/${branch}"

    stderr "## Configured branch '${branch}' to track '${remote_name}/${branch}'"
}

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
    check_deps git

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

    # Initialize the repository (without branch config yet)
    __init_repo "$destination" "$REPO_URL" "" "$remote_name"

    # Setup deploy key
    local deploy_key_cmd
    if deploy_key_cmd=$(__find_deploy_key_cmd); then
        stderr ""
        stderr "## Setting up deploy key..."
        $deploy_key_cmd --remote "$remote_name" --no-test
    else
        stderr ""
        stderr "## Warning: git-deploy-key not found, skipping deploy key setup"
        stderr "## You may need to configure SSH authentication manually"
    fi

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

        # Checkout the branch (creates local tracking branch from remote)
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
        local key_file
        if key_file=$(__get_deploy_key_file "$remote_name"); then
            __show_key_instructions "$key_file"
        else
            stderr ""
            stderr "## Deploy key not working and key file not found."
            stderr "## Run 'git deploy-key --show' to see the public key."
        fi

        stderr ""
        stderr "## Repository prepared at: ${destination}"
        stderr "## After adding the deploy key, run this command again:"
        stderr "##   git deploy ${ORIGINAL_ARGS}"
        stderr "##"
        stderr "## Or, set it up manually for a specific branch:"
        stderr "##   cd ${destination}"
        stderr "##   git fetch"
        stderr "##   git checkout -b dev origin/dev"
        stderr ""

        stderr ""

        # Still output destination but exit with error
        echo "$destination"
        exit 1
    fi

    # Output destination for use by other scripts
    echo "$destination"
}

main "$@"
