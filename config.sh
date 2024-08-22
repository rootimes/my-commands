#!/bin/bash

# 定義所有的 alias
declare -A ALIASES
ALIASES["ll"]="ls -alF"
ALIASES["gitlocalroot"]="git config --local user.name 'rootimes' && \
    git config --local user.email 'leo32095@gmail.com'"
