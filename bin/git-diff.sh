#!/bin/sh
echo running $2 $5
diffcolor -u "$2" "$5" | cat
