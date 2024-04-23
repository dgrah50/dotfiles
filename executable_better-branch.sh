#!/bin/bash

# Define the backtitle, title, and menu for the script
BACKTITLE="Better Git Branch - From Jira Issues"
TITLE="Select the type of change"
MENU="Choose one of the following options:"

# Define the options for the type of change
OPTIONS=("feat: A new feature"
         "fix: A bug fix"
         "docs: Documentation only changes"
         "style: Changes that do not affect the meaning of the code"
         "refactor: A code change that neither fixes a bug or adds a feature"
         "perf: A code change that improves performance"
         "test: Adding missing tests"
         "merge: Putting in changes to keep up to date"
         "chore: Changes to the build process or auxiliary tools and libraries")

selected_option=$(printf "%s\n" "${OPTIONS[@]}" | fzf --height=20% --reverse --info=inline -1)
PREFIX=$(echo $selected_option | awk -F': ' '{print $1}')

# run the curl command populate the choices array
choices=$(curl -s -X GET \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  $JIRA_INSTANCE_URL | jq -r '.issues[] | "\(.key | ascii_upcase)-\(.fields.summary | ascii_downcase)"' | sed -e 's/[\/&]/-/g' -e 's/[\-]/-/g' -e 's/[\-]/-/g' -e 's/[-]/-/g' -e 's/[-]/-/g')

# Pick the jira issue from the choices with fzf and create $NEW_BRANCH_NAME
selected_issue=$(printf "%s\n" "$choices" | fzf --height=20% --reverse --info=inline -1)
NEW_BRANCH_NAME="$PREFIX/$selected_issue"

git checkout -b $NEW_BRANCH_NAME
