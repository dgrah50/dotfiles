#!/bin/bash

TEMP_FILE="/tmp/last_failed_commit_message.txt"
BACKTITLE="Better Git Commit Messages"
TITLE="Select the type of change"
MENU="Choose one of the following options:"

OPTIONS=("feat: A new feature"
         "fix: A bug fix"
         "docs: Documentation only changes"
         "style: Changes that do not affect the meaning of the code"
         "refactor: A code change that neither fixes a bug or adds a feature"
         "perf: A code change that improves performance"
         "test: Adding missing tests"
         "merge: Pulling in changes to keep up to date"
         "chore: Changes to the build process or auxiliary tools and libraries")

# Check if there's a saved commit message
if [[ -f $TEMP_FILE ]]; then
    LAST_MESSAGE=$(cat $TEMP_FILE)
    echo "A previous commit attempt failed. Would you like to reuse the last message?"
    echo "[Y] Yes, reuse: \"$LAST_MESSAGE\""
    echo "[N] No, enter a new message"
    read -p "Choose (Y/N): " REUSE_LAST

    if [[ $REUSE_LAST =~ ^[Yy]$ ]]; then
        MESSAGE=$LAST_MESSAGE
    fi
fi

# If no message has been set yet, ask the user
if [[ -z "$MESSAGE" ]]; then
    selected_option=$(printf "%s\n" "${OPTIONS[@]}" | fzf --height=20% --reverse --info=inline -1)
    PREFIX=$(echo $selected_option | awk -F': ' '{print $1}')

    read -p "Enter your commit message

$PREFIX: " MESSAGE

    # Capitalize the first letter of the commit message
    MESSAGE="$(tr '[:lower:]' '[:upper:]' <<< ${MESSAGE:0:1})${MESSAGE:1}"

    # Add a full stop as the last character if the last character is not . or ! or ?
    if [[ ${MESSAGE: -1} != "." && ${MESSAGE: -1} != "!" && ${MESSAGE: -1} != "?" ]]; then
        MESSAGE="$MESSAGE."
    fi

    MESSAGE="$PREFIX: $MESSAGE"
fi

# Attempt the commit
if git commit -m "$MESSAGE"; then
    # If commit is successful, clear the temporary file
    [[ -f $TEMP_FILE ]] && rm $TEMP_FILE
else
    # If commit fails, save the message to the temporary file
    echo "$MESSAGE" > $TEMP_FILE
    echo "Commit failed. The message has been saved for reuse."
fi
