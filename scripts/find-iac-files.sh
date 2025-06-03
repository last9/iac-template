#!/bin/bash

set -eou pipefail

# Validate cli options
function usage() {
  if [ -n "$1" ]; then
    >&2 echo -e "ERROR: $1\n"
  fi
  >&2 echo "Usage: $0 --all -git-diff"
  >&2 echo "  ---all      Find all iac files"
  >&2 echo "  --git-diff  Find iac files having git diff"
  >&2 echo ""
  >&2 echo "Example: $0 --git-diff"
}

# parse params
while [[ "$#" -gt 0 ]]; do case $1 in
    --all)      find_all_files="1"; shift;;
    --git-diff) find_git_diff_files="1"; shift;;
    *) usage "Unknown parameter passed: $1"; exit 1;
  esac
done

find_all_files=${find_all_files:-"0"}
find_git_diff_files=${find_git_diff_files:-"0"}

if [[ "$find_all_files" == "0" ]] && [[ "$find_git_diff_files" == "0" ]]; then
  >&2 echo "ERROR: Please specify at least one option --all or --git-diff"
  exit 1
fi

if [[ "$find_all_files" == "1" ]]; then
  \find "workspace" -type f | \grep -e '.yaml' | sort | uniq
fi

if [[ "$find_git_diff_files" == "1" ]]; then
  \git diff --name-only HEAD^ "workspace" | \grep -e '.yaml' | sort | uniq
fi
