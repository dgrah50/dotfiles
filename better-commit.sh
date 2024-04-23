#!/bin/bash

BACKTITLE="Better Git Commit Messages"
TITLE="Select the type of change"
MENU="Choose one of the following options:"

OPTIONS=("feat: A new feature"
         "fix: A bug fix"
         "docs: Documentation only changes"
         "style: Changes that do not affect the meaning of the code"
         "(refactor): A code change that neither fixes a bug or adds a feature"
         "perf: A code change that improves performance"
         "test: Adding missing tests"
         "merge: Pulling in changes to keep up to date"
         "chore: Changes to the build process or auxiliary tools and libraries")

selected_option=$(printf "%s\n" "${OPTIONS[@]}" | fzf --height=20% --reverse --info=inline -1)
PREFIX=$(echo $selected_option | awk -F': ' '{print $1}')

read -p "Enter your commit message

$PREFIX: " MESSAGE

# Capitalise first letter of commit message
MESSAGE="$(tr '[:lower:]' '[:upper:]' <<< ${MESSAGE:0:1})${MESSAGE:1}"

# Add a full stop as the last character if the last character is not . or ! or ?
if [[ ${MESSAGE: -1} != "." && ${MESSAGE: -1} != "!" && ${MESSAGE: -1} != "?" ]]; then
    MESSAGE="$MESSAGE."
fi

git commit -m "$PREFIX: $MESSAGE"