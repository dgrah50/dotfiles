#!/bin/bash

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

JIRA_EMAIL=""
JIRA_API_TOKEN=""
JIRA_INSTANCE_URL=""

# Make the API call and store response
response=$(curl -s -X GET \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  $JIRA_INSTANCE_URL)

# Check if curl command was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to make API request"
    exit 1
fi

# Check if response is empty
if [ -z "$response" ]; then
    echo "Error: Empty response from Jira API"
    exit 1
fi

# Check if there are any issues
issue_count=$(echo "$response" | jq '.total')
if [ "$issue_count" -eq 0 ]; then
    echo "Error: No issues found in the response"
    exit 1
fi

# Process the response and create choices
choices=$(echo "$response" | jq -r '.issues[] | "\(.key | ascii_upcase)-\(.fields.summary | ascii_downcase)"' | sed -e 's/[\/&]/-/g' -e 's/[\-]/-/g' -e 's/[\-]/-/g' -e 's/[-]/-/g' -e 's/[-]/-/g')

# Check if choices were generated
if [ -z "$choices" ]; then
    echo "Error: Failed to process issues into choices"
    exit 1
fi

# Pick the jira issue from the choices with fzf
selected_issue=$(printf "%s\n" "$choices" | fzf --height=20% --reverse --info=inline -1)

# Verify selection
if [ -z "$selected_issue" ]; then
    echo "Error: No issue selected"
    exit 1
fi

# Format the selected issue to be git branch friendly
formatted_issue=$(echo "$selected_issue" | tr '[:upper:]' '[:lower:]' | sed -e 's/[[:space:]]/-/g' -e 's/[^a-z0-9-]//g' -e 's/-\+/-/g')

NEW_BRANCH_NAME="$PREFIX/$formatted_issue"

# Create the new branch
if ! git checkout -b "$NEW_BRANCH_NAME"; then
    echo "Error: Failed to create new branch"
    exit 1
fi

echo "Successfully created and switched to branch: $NEW_BRANCH_NAME"
