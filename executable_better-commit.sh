#!/bin/bash

BACKTITLE="Better Git Commit Messages"
TITLE="Select the type of change"
MENU="Choose one of the following options:"

# Create scopes history file if it doesn't exist
SCOPES_HISTORY_FILE="$HOME/.git-scopes-history"
touch "$SCOPES_HISTORY_FILE"

OPTIONS=("feat: A new feature"
         "fix: A bug fix"
         "docs: Documentation only changes"
         "style: Changes that do not affect the meaning of the code"
         "refactor: A code change that neither fixes a bug or adds a feature"
         "perf: A code change that improves performance"
         "test: Adding missing tests"
         "merge: Pulling in changes to keep up to date"
         "chore: Changes to the build process or auxiliary tools and libraries")

selected_option=$(printf "%s\n" "${OPTIONS[@]}" | fzf --height=20% --reverse --info=inline -1)
TYPE=$(echo $selected_option | awk -F': ' '{print $1}')

# Create a temporary file for scope selection
TEMP_SCOPE_FILE=$(mktemp)
echo "none" > "$TEMP_SCOPE_FILE"
cat "$SCOPES_HISTORY_FILE" | awk '!seen[$0]++' >> "$TEMP_SCOPE_FILE"

# Use fzf with preview window for scope selection
SCOPE=$(cat "$TEMP_SCOPE_FILE" | fzf --height=20% --reverse --info=inline \
    --print-query \
    --preview-window=hidden \
    --bind "enter:accept-non-empty" \
    --bind "ctrl-d:execute(sed -i '' '/^{}$/d' '$SCOPES_HISTORY_FILE' && sed -i '' '/^{}$/d' '$TEMP_SCOPE_FILE')+reload(cat '$TEMP_SCOPE_FILE')" \
    --header="Enter scope (press enter on 'none' to skip, ctrl-d to delete)")

# Clean up temporary file
rm "$TEMP_SCOPE_FILE"

# Get the actual scope from fzf output (last line is selection, first line is query)
QUERY=$(echo "$SCOPE" | head -n1)
SELECTION=$(echo "$SCOPE" | tail -n1)

if [ "$SELECTION" = "none" ]; then
    SCOPE=""
elif [ "$SELECTION" = "" ]; then
    # If no selection but query exists, use the query as new scope
    SCOPE="$QUERY"
else
    SCOPE="$SELECTION"
fi

if [ ! -z "$SCOPE" ]; then
    TYPE="${TYPE}(${SCOPE})"
    # Add scope to history file (only if it's not empty and not 'none')
    echo "$SCOPE" >> "$SCOPES_HISTORY_FILE"
fi

read -p "Enter your commit message

$TYPE: " MESSAGE

# Capitalise first letter of commit message
MESSAGE="$(tr '[:lower:]' '[:upper:]' <<< ${MESSAGE:0:1})${MESSAGE:1}"

# Add a full stop as the last character if the last charac
ter is not . or ! or ?
if [[ ${MESSAGE: -1} != "." && ${MESSAGE: -1} != "!" && ${MESSAGE: -1} != "?" ]]; then
    MESSAGE="$MESSAGE."
fi

git commit -m "$TYPE: $MESSAGE"