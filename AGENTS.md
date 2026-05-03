# Repository Instructions

This is a public personal dotfiles repository. Treat everything committed here as
safe for public GitHub.

## Public Boundary

Do not add company-specific or professional-work tooling to this repository,
even if it does not contain credentials.

Keep the following out of this repo:

- names, paths, aliases, shortcuts, IDs, or conventions for professional systems
- helpers related to professional workflows or organization-specific tooling
- internal endpoints, object paths, service names, labels, or operational
  metadata
- CLI tools intended to be shared only inside the organization
- API keys, tokens, passwords, private keys, or other credentials

Company-specific helpers belong in the private overlay repo conventionally
checked out at `~/.ovs-dotfiles`. The public shell config may load that overlay,
but the overlay contents should not be copied here.

## Expected Pattern

Use an optional overlay path:

```zsh
${OVS_DOTFILES_DIR:-$HOME/.ovs-dotfiles}
```

Prefer this private layout for organization-specific shell code:

```text
.ovs-dotfiles/
  zsh/
    00-path.zsh
    10-infra.zsh
    20-cloud.zsh
    30-aliases.zsh
  bin/
    ovs-helper
```

When adding new public helpers here, keep them generic, reusable, and free of
organization-specific operational metadata. If a helper needs company context,
add a loader hook here and put the actual implementation in `.ovs-dotfiles`.
