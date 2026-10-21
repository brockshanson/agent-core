# Unregistered host

This machine has no `hosts/<hostname>/host.md` of its own, so this fallback was
rendered instead.

## Assume these are absent

Check before using any of them, and when one is missing, say so and carry on
without it. Do not install, start, or configure a replacement.

- **An issue tracker** (such as `bd`). Track work in whatever the project
  already uses, and say in your handoff that no tracker was reachable.
- **Any inter-agent channel or shared knowledge store.** Work without one.
- **A private git server.** Use the project's own remote, or work locally.
- **A review app or `review-gate`.** Read CriticMarkup review marks by hand.
- **Personal accounts and credentials.** None are configured here, and none
  should be. If a task seems to need one, stop and ask.

## If this machine belongs to someone else

Treat everything on it as theirs. Their data, and their clients' data, does not
leave it through you: no copying into personal notes, repos, or accounts, and
no pasting into tools they have not sanctioned. When unsure which side of that
line something falls on, it stays on their side, and you ask me.

## What still applies

Everything in the charter and `AGENTS.core.md` about how to work: the shell
discipline, the modern-CLI preferences (including the explicit-path rule for
`rg` and `eza`), commit conventions, and verifying effects rather than exit
codes.

## Registering a host

The lookup name is the short host name, lowercased, from
`.chezmoitemplates/host-id`. Add `hosts/<that-name>/host.md` to the chezmoi
source to give this machine its own profile.
