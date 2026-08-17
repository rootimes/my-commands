# Dotfiles

Cross-platform development environment configuration.

## Structure

```text
dotfiles/
├── vscode/
│   ├── common.json
│   ├── keybindings.json
│   ├── windows/
│   │   ├── settings.json
│   │   └── extensions.json
│   └── linux/
│       ├── settings.json
│       └── extensions.json
├── git/
├── shell/
└── README.md
```

VS Code settings in `common.json` apply to every operating system. Values in
`windows/settings.json` or `linux/settings.json` override matching common
settings.

Chezmoi target templates load these files and write the merged result to the
correct VS Code user directory for the current operating system. Apply changes
with `chezmoi apply`.

The thin target templates live at:

- `AppData/Roaming/Code/User/` for Windows
- `dot_config/Code/User/` for Linux

`.chezmoiignore` prevents the organizational `vscode/`, `git/`, and `shell/`
directories from being copied directly into the home directory.

Each platform folder has its own `extensions.json` inventory. Chezmoi does not
install extensions unless an automatic chezmoi script is added separately.

## Install shell aliases

```bash
CONFIG_FILE=~/.zshrc source ./shell/install.sh
```

Use `~/.bashrc` instead of `~/.zshrc` when appropriate.

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
