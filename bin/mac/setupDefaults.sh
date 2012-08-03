#!/bin/bash

# Force compatibility with django and mysql
defaults write com.apple.versioner.python Prefer-32-Bit -bool yes

# Speed up expose / mission control animation time
defaults write com.apple.dock expose-animation-duration -float 0.1
