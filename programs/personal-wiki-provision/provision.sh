# Run interactively as the owner of the wiki. Launchd only runs personal-wiki sync.
set -euo pipefail
umask 077

die() { echo "$*" >&2; exit 1; }
case "${1:-}" in
  "") register=true ;;
  --registered) register=false ;;
  *) die "Usage: personal-wiki-provision [--registered]" ;;
esac
[[ $# -le 1 && $EUID != 0 ]] || die "Run as your normal user: personal-wiki-provision [--registered]"

repo=ncwade/personal-wiki
wiki="$HOME/knowledge/personal-wiki"
remote="git@github.com:$repo.git"
title=personal-wiki-luna-deploy
fingerprint='SHA256:YgOEbk1itamZNdtd4uqHBxJ/6gcBIX66H7RQhMaJqLI'
keydir="$HOME/.ssh/personal-wiki-luna"
key="$keydir/id_ed25519"
ssh_base='ssh -F /dev/null -o IdentityAgent=none -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes'
ssh_command="$ssh_base -i ~/.ssh/personal-wiki-luna/id_ed25519"

[[ "$(git -C "$wiki" rev-parse --show-toplevel)" == "$wiki" ]] || die "Expected the wiki checkout at $wiki"
origin=$(git -C "$wiki" remote get-url --all origin)
push_url=$(git -C "$wiki" remote get-url --push --all origin)
[[ "$origin" == "$push_url" && ( "$origin" == "https://github.com/$repo.git" || "$origin" == "$remote" ) ]] ||
  die "Unexpected origin fetch/push URLs. Review the wiki checkout before provisioning."
if git -C "$wiki" config --local --get-all remote.origin.pushurl >/dev/null; then
  die "An explicit origin.pushurl exists; reconcile it before switching the wiki."
fi
existing_ssh=$(git -C "$wiki" config --local --get-all core.sshCommand || true)
[[ -z "$existing_ssh" || "$existing_ssh" == "$ssh_command" ]] || die "The wiki has a different core.sshCommand."

[[ ! -L "$keydir" && ! -L "$key" ]] || die "Unexpected symlink at the deploy-key path."
install -d -m 700 "$keydir"
tmp=$(mktemp -d "$keydir/.provision.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

# The signed Homebrew CLI integrates with the macOS desktop app. Restrict all
# secret handling to the user's runtime directory, including validation.
candidate=$key
if [[ ! -f "$key" ]]; then
  candidate="$tmp/id_ed25519"
  /opt/homebrew/bin/op read "op://Private/$title/private key?ssh-format=openssh" --out-file "$candidate"
  # OpenSSH also needs the final line terminator when a vault export omits it.
  printf '\n' >> "$candidate"
fi
ssh-keygen -y -P '' -f "$candidate" > "$tmp/key.pub"
actual=$(ssh-keygen -lf "$tmp/key.pub" -E sha256 | awk '{print $2}')
[[ "$actual" == "$fingerprint" ]] || die "The key does not match Luna's 1Password item."

if "$register"; then
  # Only public material is passed to GitHub. Preserve unrelated deploy keys.
  gh api --hostname github.com --paginate "repos/$repo/keys" > "$tmp/github-keys"
  access=$(jq -sr --arg pub "$(cut -d' ' -f1-2 "$tmp/key.pub")" '
    [ .[][] | select((.key | split(" ") | .[0:2] | join(" ")) == $pub) ]
    | if length == 0 then "missing" elif .[0].read_only then "read" else "write" end
  ' "$tmp/github-keys")
  case "$access" in
    missing) gh repo deploy-key add "$tmp/key.pub" --repo "github.com/$repo" --title "$title" --allow-write ;;
    read) die "This key is already registered read-only. Review it in the wiki repository settings." ;;
  esac
fi

# Test with only the candidate identity before switching either Git setting.
printf -v quoted_key '%q' "$candidate"
GIT_SSH_COMMAND="$ssh_base -i $quoted_key" git -C "$wiki" ls-remote --exit-code "$remote" refs/heads/main >/dev/null
if [[ "$candidate" != "$key" ]]; then
  chmod 600 "$candidate"
  mv "$candidate" "$key"
fi
git -C "$wiki" config --local core.sshCommand "$ssh_command"
if [[ "$origin" != "$remote" ]]; then
  git -C "$wiki" remote set-url origin "$remote"
fi
[[ "$(git -C "$wiki" remote get-url --all origin)" == "$remote" &&
   "$(git -C "$wiki" remote get-url --push --all origin)" == "$remote" ]] || die "Verify the wiki origin URLs."
echo "Wiki SSH access verified. Luna's Nix configuration and the checkout must both select $remote."
