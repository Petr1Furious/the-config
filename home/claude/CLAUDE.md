# Global guidance

## Working with me

When you're unsure which option I'd want, ask right when you start on the
prompt, batching the questions, not after you've built one of them.

Don't trust my ideas blindly. Check whether what I suggest would actually
work, and say so before building it if it won't, or if there's a clearly
better way.

## Simplicity

Prefer the simplest design that solves the problem. A solution made of many
rules for edge cases is a sign to step back and look for a different
approach, not to add another rule.

## User-visible text

Text that users see, such as UI labels, chat messages, log lines and command
feedback, stays short and plain. No over-explaining, no reassurance, no
filler like "Thanks for playing!". If a name needs a description to be
understood, rename it instead.

## Commits

- Don't commit unless I ask.
- Before a commit, run the project's linter and formatter and fix what they
  report, rather than silencing it. Commit only once they are clean.

## Comments

Default to no comment. Most lines are a library call, config option or
statement whose meaning a reader who knows the API already knows, and a
comment restating that is noise.

Write one only when skipping it would actually cost someone: an upstream bug
or gap whose workaround looks wrong in isolation, a value that a future edit
would plausibly "clean up" and thereby reintroduce a bug, or a constraint
that isn't discoverable by reading the code, the module it lives in, or
upstream docs (a specific machine's hardware, another service's undocumented
behavior, a past incident). If someone could reconstruct the reason in under
a minute by reading nearby code or docs, it doesn't clear the bar. Keep it to
one to three lines, and state the cause, not the investigation that found it.

### Examples

Good — records an upstream defect that makes the line look wrong otherwise:

```nix
# Upstream's setup script re-POSTs every configured list, so it exits 1 once
# one is already present, which is every run after the first.
# But it also masks other exit-1 failures.
systemd.services.pihole-ftl-setup.serviceConfig.SuccessExitStatus = [ 1 ];
```

Good — a gap in a dependency, plus the consequence of leaving it unset:

```nix
# nixarr sets this for transmission but not qbittorrent, which then leaves
# finished files group-read-only. fs.protected_hardlinks then denies
# Sonarr/Radarr the link(), and they silently copy instead.
serviceConfig.UMask = "0002";
```

Bad — explains an expected thing, and says nothing the option name doesn't:

```nix
# Enable the Jellyfin media server so it can stream the library.
jellyfin.enable = true;

# Bazarr fetches subtitles for Sonarr and Radarr content.
bazarr.enable = true;
```

Bad — narrates the investigation rather than the reason:

```nix
# Key names verified by round-tripping them through the WebUI API and
# reading back the generated ini, then confirmed against 5.2.2.
extraConfig = { ... };
```

Bad — the option name already says what it does; the "why" is one Kitty
keyboard protocol search away, not a fact locked in this repo:

```nix
# Ghostty speaks the Kitty keyboard protocol, so it sends Shift+Enter
# as a distinct sequence outside tmux; this passes that through
# instead of collapsing it to plain Enter.
set -g extended-keys always
```
