oh-my-posh init pwsh --config 'C:\Users\ru\AppData\Local\Programs\oh-my-posh\themes\jandedobbeleer.omp.json' | Invoke-Expression

function chezmoi-sync-vscode {
    & (Join-Path (chezmoi source-path) 'windows\vscode\sync-from-vscode.ps1') @args
}

function chezmoi-apply-vscode {
    & (Join-Path (chezmoi source-path) 'windows\vscode\apply-profile.ps1') @args
}
