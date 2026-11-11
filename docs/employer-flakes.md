# Employer configuration flakes

Shared Home Manager profiles live in `ncwade/nix-dotfiles`; this repository assembles the Darwin desktop and CLI machine profiles. Employer host
names, local user names, Git identity rules, and employer-specific modules live
in private repositories under `ncwade`.

The `defense-unicorns` input points to `ncwade/nix-config-defense-unicorns` over
SSH. The parent lock file pins the employer repository to an exact commit.
Fetching it requires GitHub SSH access to that private repository. This is also
required for a fresh full-flake validation on a personal machine.

The employer flake exports `lib.darwinHosts`, an attribute set keyed by host
name. Each host selects a shared `profile` (`desktop` or `cli`), specifies its
`username`, and provides `extraModules`. The parent builds these hosts with the
same pinned Nixpkgs, nix-darwin, and Home Manager used by its personal hosts.
The employer flake supplies modules and host definitions; complete system
builds are exposed through this repository's `darwinConfigurations`.

`homeManagerModules.default` supplies employer Git rules. The personal host
imports these explicitly to preserve work-repository email selection. Shared
user profiles contain only the personal identity rules. Personal-wiki support
remains opt-in on the personal host and disabled on employer hosts.

## Editing and updating

Keep the employer checkout beside this repository. Validate local edits before
publishing them:

```console
nix flake check --no-build --all-systems --no-write-lock-file \
  --override-input defense-unicorns path:../nix-config-defense-unicorns
```

After committing and pushing the employer changes, update only that input:

```console
nix flake update defense-unicorns
nix flake check --no-build --all-systems
```

Commit the resulting `flake.lock` change. Roll back an employer update by
restoring the prior lock-file revision. The employer repository retains the authoritative employer settings; old anonymized parent history is not a source for restoring those details.

The employer flake has no dependency on this parent, avoiding circular inputs.
Additional employer flakes can export the same interface and be composed into
`darwinConfigurations` when needed.

## Privacy

The input URL and pinned revision remain visible in this repository. Employer
configuration is fetched into the local Nix store, so private repositories are
not a mechanism for storing secret credentials. This repository imports only the cleaned machine history. GitHub-held references in the former `nix-config` repository are separate from this repository.
