#!/bin/bash
ctx=$(kubectl config current-context 2>/dev/null | sed 's/.*_//')
if [ -z "$ctx" ]; then
  echo "-"
elif echo "$ctx" | grep -qi 'dev'; then
  echo "$ctx"
else
  echo "#[fg=red,bold]$ctx#[fg=default,nobold]"
fi
