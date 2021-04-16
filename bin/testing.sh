#!/usr/bin/env bash

echo "Sleeping $1 seconds"
sleep "$1"

echo "Exiting with code $2"
exit "$2"
