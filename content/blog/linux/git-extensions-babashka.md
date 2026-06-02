---
title: "Git extensions in Babashka"
date: 2026-06-02T00:00:00-06:00
tags: ['linux', 'git', 'clojure', 'babashka']
---

In a [previous post]({{< ref "/blog/linux/git-extensions" >}}), I
introduced `git_extensions.sh` -- a monolithic bash script providing
custom git subcommands (`git vendor`, `git deploy`, `git deploy-key`,
`git remote-proto`). It worked fine. It also weighed in at 1,590 lines
of bash, with global variables named things like
`VENDOR_SSH_PORT` and URL parsing done through cascading regex in
`BASH_REMATCH`. The kind of code where adding a feature means holding
your breath and hoping `set -eo pipefail` catches whatever you break.

So I ported it to [Babashka](https://babashka.org/).

## Why Babashka?

Babashka is a fast-starting Clojure scripting runtime. It ships as a
single static binary, starts in under 50ms, and gives you a real
language with real data structures instead of a stringly-typed
minefield.

The pitch for porting a bash script to Babashka:

- **Maps instead of globals.** URL parsing returns `{:host "github.com"
  :path "user/repo"}` instead of setting `REMOTE_PROTO_HOST` and
  praying nobody clobbers it.
- **Explicit parameters instead of `cd`.** The bash version relies on
  `cd "$dest"` to set the working directory for subsequent git
  commands. The Babashka version passes `:dir` explicitly to every
  process call. No spooky action at a distance.
- **Actual testable functions.** Each function takes arguments and
  returns values. No subshell surprises, no nameref tricks (`local
  -n`), no quoting emergencies.
- **63% less code.** 580 lines of Clojure vs 1,590 lines of bash, with
  identical functionality and CLI interface.

The tradeoff is a runtime dependency -- you need `bb` on your PATH.
But if you're already using Nix (and if you're reading this blog, you
probably are), that's a non-issue.

## What changed

Nothing, from the user's perspective. The CLI is identical:

```bash
git vendor enigmacurry/sway-home
git deploy git@github.com:user/repo.git
git deploy-key list
git remote-proto ssh --port 2222
```

Same flags, same output, same symlink dispatch trick. The script
detects its invoked name and dispatches accordingly, with a fallback
to first-argument dispatch:

```bash
# Via symlink (git finds git-vendor in PATH):
git vendor org/repo

# Direct invocation:
bb git_extensions.bb vendor org/repo
```

## How the port went

Most of the translation was mechanical. Bash patterns have direct
Clojure equivalents:

| Bash | Babashka |
|------|----------|
| `[[ "$url" =~ ^git@([^:]+):(.+)$ ]]` | `(re-matches #"git@([^:]+):(.+)" url)` |
| `REPO_URL="${BASH_REMATCH[1]}"` | `(let [[_ host path] (re-matches ...)])` |
| `local -n _host=$2` | Just return a map |
| `check_deps git ssh-keygen` | `(check-deps "git" "ssh-keygen")` |
| `git remote get-url origin` | `(git-out dir "remote" "get-url" "origin")` |
| `awk '...' "$config_file" > "$tmp_file"` | Line processing with `loop`/`recur` |

The SSH config manipulation (adding/removing Host blocks) was the most
interesting part. The bash version uses awk with state tracking. The
Clojure version does the same thing with a `loop` that tracks a
`skip` flag -- structurally identical, but without awk's implicit line
iteration.

The one genuinely tricky part was symlink detection. Babashka resolves
`*file*` to the actual script, not the symlink. The solution tries two
strategies: on Linux it reads `/proc/self/cmdline` (the null-separated
argv), and on macOS/BSD it falls back to `ps -p <pid> -o args=`. Both
scan the process command line for an argv entry starting with `git-`.

## Installation

If you use my [sway-home](https://github.com/EnigmaCurry/sway-home)
config with home-manager, it's already wired up -- the symlinks now
point to `git_extensions.bb`.

For manual installation, you'll need
[Babashka](https://github.com/babashka/babashka#installation)
installed, then:

```bash
## Download the script and make it executable:
curl -Lo ~/.local/bin/git_extensions.bb \
  https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/git/git_extensions.bb
chmod +x ~/.local/bin/git_extensions.bb

## Create symlinks for each extension:
ln -s git_extensions.bb ~/.local/bin/git-vendor
ln -s git_extensions.bb ~/.local/bin/git-deploy
ln -s git_extensions.bb ~/.local/bin/git-deploy-key
ln -s git_extensions.bb ~/.local/bin/git-remote-proto
```

The bash version still works and isn't going anywhere. Use whichever
you prefer.

## The script

 * [Download the script from this direct link](https://raw.githubusercontent.com/EnigmaCurry/blog.rymcg.tech/master/src/git/git_extensions.bb)

{{< code file="/src/git/git_extensions.bb" language="clojure" >}}
