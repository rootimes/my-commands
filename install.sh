#!/bin/bash

# 加載配置文件
source ./config.sh

# 函數：檢查並增加 alias
add_alias_if_not_exists() {
    local alias_name="$1"
    local alias_command="$2"
    local full_alias="alias $alias_name='$alias_command'"

    # 檢查配置文件中是否已經存在該 alias
    if grep -Fxq "$full_alias" "$CONFIG_FILE"; then
        echo "Alias '$alias_name' already exists in $CONFIG_FILE."
    else
        echo "Creating alias '$alias_name'..."
        # 創建 alias
        alias "$alias_name"="$alias_command"
        # 將 alias 添加到配置文件中
        echo "$full_alias" >>"$CONFIG_FILE"
    fi
}

# 定義要操作的配置文件，例如 ~/.bashrc 或 ~/.zshrc
CONFIG_FILE=${CONFIG_FILE:-~/.bashrc}

# 遍歷所有在 config.sh 中定義的 alias，並安裝它們
for alias_name in "${!ALIASES[@]}"; do
    add_alias_if_not_exists "$alias_name" "${ALIASES[$alias_name]}"
done

# 重新加載配置文件
source "$CONFIG_FILE"
echo "Configuration reloaded."
echo "Installation completed!"
