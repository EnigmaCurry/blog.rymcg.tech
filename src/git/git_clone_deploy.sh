#!/usr/bin/env bash
set -euo pipefail

URL="${1:-}"
DEST_DIR="${2:-}"

if [ -z "$URL" ]; then
  echo "usage: git clone-deploy <repo-url> [destination-path]"
  exit 1
fi

# ---- Parse the URL: Detect whether it's HTTPS or SSH
if [[ "$URL" =~ ^git@ ]]; then
  # SSH URL provided (git@github.com:owner/repo.git)
  HOST="${URL#git@}"
  HOST="${HOST%%:*}"
  PATH_PART="${URL#*:}"
  OWNER="${PATH_PART%%/*}"
  REPO="$(basename "$PATH_PART" .git)"
else
  # HTTPS URL provided (https://github.com/owner/repo.git)
  proto_removed="${URL#*://}"
  HOST="${proto_removed%%/*}"
  PATH_PART="${proto_removed#*/}"
  OWNER="${PATH_PART%%/*}"
  REPO="$(basename "$PATH_PART" .git)"
fi

ALIAS="${HOST}-${OWNER}-${REPO}"
KEY="$HOME/.ssh/id_deploy_${HOST}_${OWNER}_${REPO}"

echo
echo "Repository : $OWNER/$REPO"
echo "Host       : $HOST"
echo "SSH alias  : $ALIAS"
echo "Key path   : $KEY"
echo

# ---- Generate key if needed
if [ ! -f "$KEY" ]; then
  echo "Generating SSH deploy key..."
  ssh-keygen -t ed25519 -N "" -f "$KEY"
else
  echo "SSH key already exists, reusing it."
fi

# ---- Ensure SSH config entry exists
if ! grep -q "Host $ALIAS" "$HOME/.ssh/config" 2>/dev/null; then
  echo "Updating ~/.ssh/config"
  cat >> "$HOME/.ssh/config" <<EOF

# deploy key for $OWNER/$REPO
Host $ALIAS
  HostName $HOST
  User git
  IdentityFile $KEY
  IdentitiesOnly yes
EOF
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ADD THIS DEPLOY KEY TO THE REPOSITORY:"
echo
cat "${KEY}.pub"
echo
echo "Go to:"
echo "  Repository Settings → Deploy keys"
echo "  (read-only is usually sufficient)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# ---- Pause for user
read -rp "Press Enter once the deploy key has been added…"

# ---- Generate the correct SSH URL for cloning
if [[ "$URL" =~ ^git@ ]]; then
  # If the URL is already SSH, no need to prepend `git@`
  REPO_URL="$URL"
else
  # Otherwise, build the SSH URL
  REPO_URL="git@$ALIAS:$OWNER/$REPO.git"
fi

# ---- Determine the destination directory
if [ -z "$DEST_DIR" ]; then
  # Default directory (repo name)
  DEST_DIR="$REPO"
fi

echo
echo "Cloning repository into $DEST_DIR using deploy key…"

# ---- Explicitly use the deploy key only for this git command
GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes" git clone "$REPO_URL" "$DEST_DIR"

echo
echo "✓ Clone complete"

# ---- Update the remote URL to use the alias
cd "$DEST_DIR"
git remote set-url origin "git@$ALIAS:$OWNER/$REPO.git"

echo
echo "The remote URL has been updated to use the alias."
