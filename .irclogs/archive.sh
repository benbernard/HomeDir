#!/bin/zsh
foreach i (bitlbee freenode) { mv $i gaol/$i.`date +%Y-%m-%d` }
