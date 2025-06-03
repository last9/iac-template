#!/bin/bash

set -eou pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# Check for pre-requisite commands
# shellcheck disable=SC2043
for cmd in l9iac jq; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo >&2 "ERROR: Did not find command - $cmd"
    exit 1
  fi
done

# Validate cli options
function usage() {
  if [ -n "$1" ]; then
    echo >&2 -e "ERROR: $1\n"
  fi
  echo >&2 "Usage: $0 [-a action] [-i input_file]"
  echo >&2 "  -p, --plan          action=plan"
  echo >&2 "  -a, --apply         action=apply"
  >&2 echo "  --run-input-file      run action for input file"
  >&2 echo "  --run-all-files       run action for all iac files"
  >&2 echo "  --run-git-diff-files  run action for git diff files"
  # TODO - to fix - when running iac in while loop, cannot prompt user when -y/--yes not supplied - hence assuming apply == apply -y
  # >&2 echo "  -y, --yes           add yes for apply"
  echo >&2 ""
}

# parse params
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -a | --apply)
    action="apply"
    shift
    ;;
  -p | --plan)
    action="plan"
    shift
    ;;
  #  -y | --yes) apply_yes="1"; shift;;
  --run-input-file) run_input_file="$2"; shift; shift;;
  --run-all-files) run_all_files="1"; shift;;
  --run-git-diff-files) run_git_diff_files="1"; shift;;
  *)
    usage "Unknown parameter passed: $1"
    exit 1
    ;;
  esac
done

action=${action:-""}
if [[ $action == "" ]]; then
  usage "action empty or not specified"
  exit 1
fi
if [[ "$action" != "plan" ]] && [[ "$action" != "apply" ]]; then
  usage "Invalid action=$action"
  exit 1
fi

run_git_diff_files=${run_git_diff_files:-"0"}
run_all_files=${run_all_files:-"0"}
run_input_file=${run_input_file:-""}
iac_target_files_list="/tmp/iac_target_files.txt"

if [[ $run_input_file != "" ]]; then
  if ! [[ -f "$run_input_file" ]]; then
    >&2 echo "ERROR: input_file=$run_input_file does not exist."
    exit 1
  fi
  echo "$run_input_file" > $iac_target_files_list
fi

if [[ $run_all_files == "1" ]]; then
  "scripts/find-iac-files.sh" --all > $iac_target_files_list
fi

if [[ $run_git_diff_files == "1" ]]; then
  "scripts/find-iac-files.sh" --git-diff > $iac_target_files_list
fi

set +e
if ! \grep -q '.yaml' $iac_target_files_list; then
  >&2 echo "STATUS: l9iac did not find any files to process"
  exit 0
fi
set -e

# LAST9_API_CONFIG_STR=${LAST9_API_CONFIG_STR:-""}
# iac_config_file="/tmp/.last9-iac.config.json"
# backup_s3_bucket=""

# if [[ "$LAST9_API_CONFIG_STR" == "" ]]; then
#   echo >&2 "STATUS: Environment variable LAST9_API_CONFIG_STR not set."
#   exit 1
# fi

# if ! echo -e "$LAST9_API_CONFIG_STR" | jq >$iac_config_file; then
#   echo >&2 "ERROR: Failed to parse environment variable LAST9_API_CONFIG_STR - invalid json"
#   exit 1
# fi

# backup_s3_bucket=${LAST9_BACKUP_S3_BUCKET:-""}
# if [[ $backup_s3_bucket == "" ]]; then
#   echo >&2 "ERROR: Environment variable LAST9_BACKUP_S3_BUCKET not set"
#   exit 1
# fi

# # aws sts assume-role --role-session-name last9_2 --duration-seconds 3600 --role-arn "arn:aws:iam::652845092827:role/last9-iac-probo-state" --external-id "last9-dev-probo-Xm82"
# # Check if assume role is set - if yes use it
# AWS_ASSUME_ROLE_ARN=${AWS_ASSUME_ROLE_ARN:-""}
# AWS_ASSUME_ROLE_EXTERNAL_ID=${AWS_ASSUME_ROLE_EXTERNAL_ID:-""}
# if [[ "$AWS_ASSUME_ROLE_ARN" != "" ]] && [[ "$AWS_ASSUME_ROLE_EXTERNAL_ID" != "" ]]; then
#   session_name="$(date +%s)_last9"
#   echo >&2 "STATUS: using AWS_ASSUME_ROLE_ARN=$AWS_ASSUME_ROLE_ARN session=$session_name"
#   duration_seconds=3600
#   if ! aws sts assume-role --role-session-name "$session_name" --duration-seconds "$duration_seconds" --role-arn "$AWS_ASSUME_ROLE_ARN" \
#     --external-id "$AWS_ASSUME_ROLE_EXTERNAL_ID" | "$SCRIPT_DIR/assume-role-output-to-env.sh" >/tmp/assume-role-creds.sh 2>&1; then
#     echo >&2 "ERROR: Failed to assume role $AWS_ASSUME_ROLE_ARN"
#     exit 1
#   fi
#   # shellcheck disable=1091
#   source "/tmp/assume-role-creds.sh"
#   echo >&2 "STATUS: assumed role AWS_ASSUME_ROLE_ARN=$AWS_ASSUME_ROLE_ARN"
#   echo >&2 "STATUS: Dumping new identity"
#   aws sts get-caller-identity
# fi

# if ! aws s3 ls "$backup_s3_bucket" >/dev/null; then
#   echo >&2 "ERROR: backup_s3_bucket=$backup_s3_bucket - failed to check existence"
#   exit 1
# fi

# # shellcheck disable=2001
# backup_s3_bucket=$(echo "$backup_s3_bucket" | sed 's:/*$::')

# echo >&2 "STATUS: Using iac_config_file=$iac_config_file backup_s3_bucket=$backup_s3_bucket"


# Load config
>&2 echo "------------------------"

config_file='.last9.config.json'
env_vars_file="/tmp/.last9.config.sh"

>&2 echo "------------------------"
if [[ -f $config_file ]]; then
  if ! "$SCRIPT_DIR/load-config.sh" --config-file "$config_file" --output-file "$env_vars_file" --cache-config; then
    >&2 echo "ERROR: Failed to load config file $config_file"
    exit 1
  fi
else
  if ! "$SCRIPT_DIR/load-config.sh" --output-file "$env_vars_file"; then
    >&2 echo "ERROR: Failed to load config from env vars"
    exit 1
  fi
fi

# shellcheck disable=1090
source $env_vars_file

>&2 echo "------------------------"
# Validate loaded config
if ! "$SCRIPT_DIR/validate-config.sh" --env-vars-file "$env_vars_file"; then
  >&2 echo "ERROR: Failed to validate env vars file $env_vars_file"
  exit 1
fi

# shellcheck disable=1090
# To load assume role vars if any
source $env_vars_file

iac_config_file="/tmp/.last9-iac.config.json"

# Backup iac config file as we will update "state_lock_file_path" in it later
cp "$iac_config_file" "${iac_config_file}.orig"

while read -r input_file; do

  echo >&2 "------------------------"
  echo >&2 "STATUS: file=$input_file action=$action"

  input_file_dir=$(dirname "$input_file")
  input_file_name=$(basename "$input_file")
  backup_s3_bucket_dir_path="$LAST9_BACKUP_S3_BUCKET/$input_file_dir"

  if ! aws s3 cp "$input_file" "$backup_s3_bucket_dir_path/" >/dev/null; then
    echo >&2 "ERROR: Failed to copy $input_file to $LAST9_BACKUP_S3_BUCKET/$input_file_dir"
    exit 1
  fi

  lock_file_name="$(echo "$input_file_name" | cut -f1 -d'.').lock"
  remote_lock_file="$backup_s3_bucket_dir_path/$lock_file_name"
  remote_lock_bak_file="$backup_s3_bucket_dir_path/${lock_file_name}.bak"

  echo >&2 "STATUS: Updating iac config file to use lock_file=$lock_file_name"
  cp "${iac_config_file}.orig" "$iac_config_file"
  cat <<<"$(jq '.state_lock_file_path |= sub("alerting-iac-state.lock"; "'"$lock_file_name"'")' <$iac_config_file)" >"$iac_config_file"

  if aws s3 ls "$remote_lock_file" >/dev/null; then
    echo >&2 "STATUS: Found remote_lock_file=$remote_lock_file"
    echo >&2 "STATUS: Copying remote_lock_file=$remote_lock_file to input_file_dir=$input_file_dir"
    if ! aws s3 cp "$remote_lock_file" "$input_file_dir" >/dev/null; then
      echo >&2 "ERROR: Failed to copy remote_lock_file=$remote_lock_file to input_file_dir=$input_file_dir"
      exit 1
    fi
  else
    echo >&2 "STATUS: Did not find remote_lock_file=$remote_lock_file"
  fi

  if aws s3 ls "$remote_lock_bak_file" >/dev/null; then
    echo >&2 "STATUS: Found remote_lock_bak_file=$remote_lock_bak_file"
    echo >&2 "STATUS: Copying remote_lock_bak_file=$remote_lock_bak_file to input_file_dir=$input_file_dir"
    if ! aws s3 cp "$remote_lock_bak_file" "$input_file_dir" >/dev/null; then
      echo >&2 "ERROR: Failed to copy remote_lock_bak_file=$remote_lock_bak_file to input_file_dir=$input_file_dir"
      exit 1
    fi
  else
    echo >&2 "STATUS: Did not find remote_lock_bak_file=$remote_lock_bak_file"
  fi

  cd "$input_file_dir"

  if [[ $action == "plan" ]]; then
    set -x
    set +e
    if ! l9iac -mf "$input_file_name" -c "$iac_config_file" plan; then
      echo >&2 "STATUS: file=$input_file action=$action status=failed"
      exit 1
    fi
    set -e
    set +x
  else
    set -x
    set +e
    if ! l9iac -mf "$input_file_name" -c "$iac_config_file" apply -y; then
      echo >&2 "STATUS: file=$input_file action=$action status=failed"
      exit 1
    fi
    set -e
    set +x

    echo >&2 "STATUS file=$input_file action=copy_lock_file"
    if ! aws s3 cp "$lock_file_name" "$remote_lock_file" >/dev/null; then
      echo >&2 "STATUS file=$input_file action=copy_lock_file status=failed"
      exit 1
    fi
    echo >&2 "STATUS file=$input_file action=copy_lock_file status=success"
    echo >&2 "STATUS file=$input_file action=copy_lock_file source=$lock_file_name dest=$remote_lock_file status=success"

    if [[ -f "${lock_file_name}.bak" ]]; then
      echo >&2 "STATUS file=$input_file action=copy_lock_bak_file"
      if ! aws s3 cp "${lock_file_name}.bak" "$remote_lock_bak_file" >/dev/null; then
        echo >&2 "STATUS file=$input_file action=copy_lock_bak_file status=failed"
        exit 1
      fi
    fi
    echo >&2 "STATUS file=$input_file action=copy_lock_bak_file source=${lock_file_name}.bak dest=$remote_lock_bak_file status=success"

  fi

  echo >&2 "STATUS: file=$input_file action=$action status=success"

  if [[ -f $lock_file_name ]]; then
    echo >&2 "STATUS: file=$input_file lock_file=$lock_file_name status=removing_local_lock_file"
    rm -f "$lock_file_name"
  fi

  if [[ -f "${lock_file_name}.bak" ]]; then
    echo >&2 "STATUS: file=$input_file lock_file_bak=${lock_file_name}.bak status=removing_local_lock_bak_file"
    rm -f "${lock_file_name}.bak"
  fi
  echo >&2 "------------------------"

  cd - >/dev/null
done <"$iac_target_files_list"
