# Dotfiles

Cross-platform development environment configuration.

## Structure

```text
dotfiles/
├── windows/vscode/
│   ├── profiles/
│   │   ├── default/
│   │   │   ├── settings.json
│   │   │   ├── keybindings.json
│   │   │   └── extensions.json
│   │   └── <named-profile>/
│   │       ├── settings.json
│   │       └── extensions.json
│   ├── apply-profile.ps1
│   └── sync-from-vscode.ps1
├── linux/vscode/profiles/
│   ├── default/
│   └── <named-profile>/
├── git/
├── shell/
└── README.md
```

Every VS Code Profile is self-contained under
`<platform>/vscode/profiles/<name>/` with its own complete `settings.json` and
`extensions.json`. Windows and Linux are separate sources; settings and
extensions are never inherited or merged across Profiles or platforms. Each
platform's Default Profile also owns its `keybindings.json` file.

Chezmoi target templates write the Default Profile settings and keybindings to
the correct VS Code user directory. Apply changes with `chezmoi apply`.

The thin target templates live at:

- `AppData/Roaming/Code/User/` for Windows
- `dot_config/Code/User/` for Linux

`.chezmoiignore` prevents the organizational `vscode/`, `windows/`, `linux/`,
`git/`, and `shell/` directories from being copied directly into the home
directory.

Profile settings are preserved as JSONC. Each `extensions.json` contains only
portable extension IDs and omits VS Code's machine-specific paths and
installation metadata.

### Synchronize VS Code Profiles on Windows

The managed PowerShell Profile defines `chezmoi-apply-vscode` and
`chezmoi-sync-vscode`. After updating the Profile in an already-open PowerShell
session, reload it with:

```powershell
chezmoi apply $PROFILE
. $PROFILE
```

`$PROFILE` is the path to the current PowerShell Profile file. The leading dot
is PowerShell's dot-source operator, which loads the file into the current
session so its functions become immediately available. `chezmoi apply` only
updates the file on disk and cannot modify commands already loaded into a
running PowerShell process. A newly opened PowerShell session loads the Profile
automatically, so the dot-source command is only needed for an existing
session. This is equivalent to `source ~/.bashrc` after changing a Bash config.

Apply one Windows Profile by source folder name:

```powershell
chezmoi-apply-vscode default
chezmoi-apply-vscode angular
```

Apply every Windows Profile, or preview without writing:

```powershell
chezmoi-apply-vscode all
chezmoi-apply-vscode all -DryRun
```

Add `-SkipExtensions` to apply settings without calling the VS Code CLI.
Profile names are resolved under `windows/vscode/profiles/`; they are not
passed to `chezmoi apply` as managed target paths.

`.chezmoiscripts/run_after_vscode-profiles.ps1.tmpl` runs after every complete
`chezmoi apply`. It:

- installs missing extension IDs for the Default Profile;
- matches each named source folder to an existing VS Code Profile by exact name;
- copies the Profile's `settings.json` to its machine-specific internal ID;
- installs missing extension IDs with `code --profile`;
- leaves additional installed extensions and `globalStorage` untouched;
- skips source Profiles that have not yet been created in VS Code.

The chezmoi hook delegates to `windows/vscode/apply-profile.ps1 all`, so manual
Profile applies and `chezmoi apply` use the same settings and extension logic.
Running the hook every time also restores extensions that were removed locally
even when the source inventories have not changed.

Preview the chezmoi changes without running scripts:

```powershell
chezmoi apply --dry-run --verbose
```

Apply files and synchronize all Profiles:

```powershell
chezmoi apply --verbose
```

### Capture VS Code changes on Windows

After changing settings or extensions in VS Code, capture the current Default
and named Profile state back into this repository:

```powershell
chezmoi-sync-vscode
```

Capture one Profile, or preview it without writing:

```powershell
chezmoi-sync-vscode windows
chezmoi-sync-vscode windows -DryRun
```

The positional Profile argument accepts `default`, any exact named Profile, or
`all` (the default). Add `-SkipExtensions` to capture settings without calling
the VS Code CLI.

The `chezmoi-sync-vscode` function is installed through the managed Windows
PowerShell Profile described above.

The capture script updates:

- `windows/vscode/profiles/default/settings.json` from the Default settings;
- `windows/vscode/profiles/default/keybindings.json` from the Default keybindings;
- `windows/vscode/profiles/default/extensions.json` from `code --list-extensions`;
- each exact-name match under `windows/vscode/profiles/<name>/` from the
  corresponding VS Code Profile settings and
  `code --profile <name> --list-extensions`.

New named Profiles found in the VS Code registry are added automatically using
a lowercase source folder name. A Profile without its own `settings.json` is
captured as an empty JSON object.

Extension IDs are captured without a blacklist or special exclusions. Preview
the files that would change without writing them:

```powershell
chezmoi-sync-vscode -DryRun
```

To capture settings and keybindings without calling the VS Code CLI:

```powershell
chezmoi-sync-vscode -SkipExtensions
```

Review the result before applying or committing it:

```powershell
git diff -- vscode
```

## Install shell aliases

```bash
CONFIG_FILE=~/.zshrc source ./shell/install.sh
```

Use `~/.bashrc` instead of `~/.zshrc` when appropriate.

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
