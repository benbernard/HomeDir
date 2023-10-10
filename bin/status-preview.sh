#!/bin/bash

FILE_NAME=$1

git -c color.status=always status -s | grep ${FILE_NAME}
echo

if git ls-files --error-unmatch ${FILE_NAME} >/dev/null 2>&1; then
    # If file is in git, print diff
    git diff --color ${FILE_NAME}
else
    # just print the file in green
    awk '{ print "\033[38;5;47m" $0 "\033[0m" }' $FILE_NAME 
fi
