# Compact Codex command display

Restores OpenAI's `Ran N commands` grouping in the Codex terminal UI. Consecutive
successful commands share one history entry; the transcript (`Ctrl+T`) retains
their command text and output. Failures remain visible. A single command may
still show its usual preview. This does not change tool execution, model input,
model settings, or command arguments.

The source patch restores [OpenAI PR #38921](https://github.com/openai/codex/pull/38921)
by reversing [its removal in PR #41893](https://github.com/openai/codex/pull/41893).
It only touches `codex-rs/tui`. This is a local customization, not an officially
supported Codex setting. Attribution and the exact base are in [NOTICE](NOTICE).

## Install

Requires Linux or macOS, Python 3.11+, Git, GitHub CLI (`gh`), Rustup, `just`,
`cargo-nextest`, `uv`, DotSlash, and the native build dependencies required by
upstream Codex.
On Debian/Ubuntu these include a C/C++ toolchain, Clang, CMake, `pkg-config`,
`libssl-dev`, and `libcap-dev`. The release pins its Rust toolchain; install its
`rustfmt` and `clippy` components too. Upstream's formatting script uses DotSlash.

From this repository:

```sh
python3 codex-compact/manage.py update --local-recipe
```

Put `~/.local/bin` before package-manager directories in `PATH`. The installer
creates `codex` and `codex-compact` launchers there, refusing to overwrite an
unrelated launcher. It leaves package-manager installations intact. Restart
Codex after installation; use `codex resume --last` to resume a session.

The first source build can take tens of minutes and requires several GiB of
free space. Subsequent builds reuse `~/.cache/codex-compact-target`.
`CARGO_BUILD_JOBS` defaults to 4 and can be overridden.

## Upgrade and switch display

```sh
codex-compact update                  # refresh this recipe, build latest stable
codex-compact update --version 0.153.4 # select an exact stable release
codex-compact update --check          # check patch application without building
codex-compact status                  # version, source commit, patch/binary hashes
codex-compact rollback                # switch to the previous installed build
codex-compact mode expanded           # official binary at the same version
codex-compact mode compact            # restore command grouping
CODEX_TOOL_DISPLAY=expanded codex     # expanded display for one launch
```

`codex update` also uses this updater. Package-manager upgrades do not update the
compact installation. Expanded mode runs the checksum-verified official release
binary; it is a launcher option, not a change to Codex's configuration schema.
Both modes use your normal Codex account, configuration, and sessions.

Each update fetches this repository into a separate maintenance checkout, gets
an official stable release tag, checks the patch, checks formatting and Clippy,
runs the complete TUI test suite, and builds the CLI. Only a successful build
with matching version checks is activated, by changing one symlink. A patch
conflict, failed test, or failed build leaves the current binary selected.
Inspect the error and retry after the recipe is fixed. The updater does not
force patch application or reset local source edits.

State and versioned binaries live in `~/.local/share/codex-compact`; override this
with `CODEX_COMPACT_HOME`. Keep that variable set for subsequent launches if you
use a custom location. Rollback keeps both versions and can be toggled again.
Older source/build directories are retained for diagnosis; no automatic cleanup
removes your rollback build.

Some release tags update workspace package versions without updating their
lockfile. The build repairs only these local version entries. It verifies that
all external dependencies match the tagged lockfile; it never runs a general
dependency update. Release builds disable LTO and debug artifacts to keep local
build time and disk use manageable.

## Maintain the patch

The scheduled GitHub workflow checks this recipe against the latest stable tag;
it does not publish binaries or install upgrades. A clean patch check proves
only that the patch applies. The updater's build and TUI tests remain the gate
before activation.

To refresh the patch, start from the new official tag, port only the UI change,
then save `git diff --binary -- codex-rs/tui` into the patch file. Run upstream's
TUI checks and the updater tests before committing. `update --local-recipe`
uses your current recipe without fetching remote changes; `--source PATH`
reuses a developer checkout only if it matches the expected patch.

```sh
python3 -m unittest discover -s codex-compact -p 'test_*.py'
```

If upstream gains a supported equivalent, remove the patch and switch back to
the official binary. To uninstall the launchers, remove `~/.local/bin/codex`
and `~/.local/bin/codex-compact`, then run `rehash` in zsh. Your package-manager
Codex installation and normal `~/.codex` data remain available.
