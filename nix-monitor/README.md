# Nix Monitor

Nix Monitor compares a flake's locked Nixpkgs revision with its configured
upstream source, or the local NixOS revision with a fallback remote branch, and shows
NixOS generations, store size, closure size, system and user package counts,
and update status from the bar.

## Plugin

| Field | Value |
| --- | --- |
| ID | `luisrocha/nix-monitor` |
| Entries | Bar widget: `nix-monitor`; panel: `panel`; service: `service` |

## Requirements

This plugin is intended for NixOS. It uses `nix`, `nixos-version`,
`nixos-rebuild`, `nix-store`, and `git`, plus the standard commands `du`, `cat`, `read`, `echo`, `awk`,
`grep`, `tail`, `wc`, `kill`, and `pkill`. Home Manager generation information
is shown when `home-manager` is available.

## Usage

Add the `nix-monitor` widget to a bar. Click it to open a panel showing local
and remote Nixpkgs revisions, NixOS and Home Manager generations, store usage,
system and user package counts, and update controls. Select the package summary
at the bottom to open a package view with System and User tabs and a bounded
scrollable list. Select **Back to overview** or any package row to return to the
main panel. Opening the panel always starts with the overview.

Open the panel directly with:

```sh
noctalia msg panel-toggle luisrocha/nix-monitor:panel
```

Set `flake_path`, `flake_input`, and `nixos_configuration` to make **Update**
update the monitored input and rebuild that flake output. `update_command` can
still override the generated command. **Optimize** runs the configured command
`nix-store --optimise -vv`. **Clean** runs the configured cleanup command, which
defaults to `nix-collect-garbage -d`. All commands open in a terminal so you can
review their output.

## Settings

Update behavior:

| Setting | Default | Description |
| --- | --- | --- |
| `update_check_interval` | `60` | Minutes between remote revision checks. |
| `update_check_duration_threshold` | `5` | Minutes before an update check is cancelled. |
| `generation_check_interval` | `60` | Minutes between NixOS and Home Manager generation checks. |
| `system_stats_check_interval` | `60` | Minutes between store and package-statistics checks. |
| `system_stats_check_duration_threshold` | `15` | Minutes before a statistics check is cancelled. |
| `show_update_check_notification` | `false` | Notifies when an update check starts and finishes. |
| `show_update_available_notification` | `true` | Notifies when a newer revision is available. |
| `flake_path` | *(empty)* | Directory containing the flake whose input should be monitored. |
| `flake_input` | `nixpkgs` | Input read from that flake's lock data and upstream source. |
| `nixos_configuration` | *(empty)* | NixOS configuration output rebuilt after updating the monitored input. |
| `branch` | `nixos-unstable` | Fallback branch used when `flake_path` is empty. |
| `update_command` | *(empty)* | Optional override for the generated update and rebuild command. |
| `optimize_command` | `nix-store --optimize -vv` | Command launched by the panel's **Optimize** button. |
| `clean_command` | `nix-collect-garbage -d` | Command launched by the panel's **Clean** button. |
| `close_on_enter` | `true` | Keeps the command terminal open until Enter is pressed. |

Widget appearance:

| Setting | Default | Description |
| --- | --- | --- |
| `show_text` | `true` | Shows status text beside the glyph. |
| `colorize_text` | `false` | Colors status text using the current state color. |
| `show_glyph` | `true` | Shows the status glyph. |
| `colorize_glyph` | `true` | Colors the glyph using the current state color. |
| `up_to_date_glyph` / `up_to_date_color` | `rosette-discount-check` / `#57ff57` | Up-to-date appearance. |
| `checking_glyph` / `checking_color` | `loader-3` / `#ffeb57` | Checking appearance. |
| `update_available_glyph` / `update_available_color` | `cloud-download` / `#ff5757` | Update-available appearance. |
| `unknown_glyph` / `unknown_color` | `cloud-question` / `on_surface` | Unknown-state appearance. |

## Notes

Package details compare **Current** versions evaluated from the configured flake's
existing lockfile with **Newest** versions after updating its selected input in
a temporary copy. This follows the built-in Update action and includes integrated
Home Manager packages for the current user. Custom update commands cannot be
predicted and display an unavailable comparison. Multiple versions of the same
package are grouped. These are evaluated configuration
versions, which can differ from the running generation until it is rebuilt.
The list, summary, and tab counts show only existing packages whose versions
change. Unchanged packages, additions, and removals are excluded. A successful
comparison with no changes displays zero and **No package updates**. Package
comparisons run with startup, scheduled, and manual update checks. Opening the
panel or package details displays the cached result without starting a new check.

Package comparisons run `sh`, `cp`, `mktemp`, `rm`, `nix-instantiate`, and Nix evaluation. They may download
flake inputs and write to the Nix cache, but never rebuilds or activates a system.
The original flake and lockfile are not changed.

When `flake_path` is configured, the plugin reads the locked revision and the
GitHub owner, repository, and ref for `flake_input` from the flake itself. The
branch setting is only used by the legacy non-flake mode. Remote checks contact
the resulting Nixpkgs Git source. The service writes
temporary revision, size, and PID files under Noctalia's state directory and
terminates overdue helper processes using the declared process tools.
