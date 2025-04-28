#!/bin/bash

TEMP_FILE="/tmp/last_failed_commit_message.txt"
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

# Initialize MESSAGE variable
MESSAGE=""

# Check if there's a saved commit message
if [[ -f $TEMP_FILE ]]; then
    LAST_MESSAGE=$(cat $TEMP_FILE)
    echo "A previous commit attempt failed. Would you like to reuse the last message?"
    echo "[Y] Yes, reuse: \"$LAST_MESSAGE\""
    echo "[N] No, enter a new message"
    read -p "Choose (Y/N): " REUSE_LAST

    if [[ $REUSE_LAST =~ ^[Yy]$ ]]; then
        MESSAGE=$LAST_MESSAGE
        # Clear the temp file now that we're reusing it
        rm $TEMP_FILE
    fi
fi

# If no message has been set yet (either no failed commit or user chose not to reuse), ask the user
if [[ -z "$MESSAGE" ]]; then
    selected_option=$(printf "%s\n" "${OPTIONS[@]}" | fzf --height=20% --reverse --info=inline -1)
    TYPE=$(echo $selected_option | awk -F': ' '{print $1}')

    # Create a temporary file for scope selection
    TEMP_SCOPE_FILE=$(mktemp)
    echo "none" > "$TEMP_SCOPE_FILE"
    # Ensure unique entries from history
    cat "$SCOPES_HISTORY_FILE" | awk '!seen[$0]++' >> "$TEMP_SCOPE_FILE"

    # Use fzf with preview window for scope selection
    SCOPE_OUTPUT=$(cat "$TEMP_SCOPE_FILE" | fzf --height=20% --reverse --info=inline \
        --print-query \
        --preview-window=hidden \
        --bind "enter:accept-non-empty" \
        --bind "ctrl-d:execute(sed -i '' '/^{}$/d' '$SCOPES_HISTORY_FILE' && sed -i '' '/^{}$/d' '$TEMP_SCOPE_FILE')+reload(cat '$TEMP_SCOPE_FILE')" \
        --header="Enter scope (press enter on 'none' to skip, ctrl-d to delete)")

    # Clean up temporary scope file
    rm "$TEMP_SCOPE_FILE"

    # Get the actual scope from fzf output (last line is selection, first line might be query)
    QUERY=$(echo "$SCOPE_OUTPUT" | head -n1)
    SELECTION=$(echo "$SCOPE_OUTPUT" | tail -n1)

    SCOPE="" # Initialize scope
    if [ "$SELECTION" = "none" ]; then
        SCOPE=""
    elif [ -z "$SELECTION" ] && [ ! -z "$QUERY" ]; then
         # If no selection but query exists, use the query as new scope
         SCOPE="$QUERY"
    elif [ ! -z "$SELECTION" ]; then
        SCOPE="$SELECTION"
    fi

    # If a scope was entered (and not 'none'), add it to the type and history
    if [ ! -z "$SCOPE" ]; then
        TYPE="${TYPE}(${SCOPE})"
        # Add scope to history file if it's not already there
        grep -qxF "$SCOPE" "$SCOPES_HISTORY_FILE" || echo "$SCOPE" >> "$SCOPES_HISTORY_FILE"
    fi

    # Get the commit message subject
    read -p "Enter your commit message subject

$TYPE: " SUBJECT

    # Capitalize the first letter of the commit message subject
    SUBJECT="$(tr '[:lower:]' '[:upper:]' <<< ${SUBJECT:0:1})${SUBJECT:1}"

    # Add a full stop as the last character if the last character is not . or ! or ?
    if [[ ${SUBJECT: -1} != "." && ${SUBJECT: -1} != "!" && ${SUBJECT: -1} != "?" ]]; then
        SUBJECT="$SUBJECT."
    fi

    # Construct the final message
    MESSAGE="$TYPE: $SUBJECT"
fi

# Attempt the commit
if git commit -m "$MESSAGE"; then
    # If commit is successful, clear the temporary file (it might exist if a previous attempt failed but wasn't reused)
    [[ -f $TEMP_FILE ]] && rm $TEMP_FILE
else
    # If commit fails, save the message to the temporary file
    echo "$MESSAGE" > $TEMP_FILE
    echo "Commit failed. The message has been saved for reuse."
    exit 1 # Exit with error status
fi

exit 0 # Exit with success status
