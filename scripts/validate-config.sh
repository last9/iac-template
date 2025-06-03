#!/bin/bash

set -eou pipefail

# TODO
# 1. Add caching - if multiple calls are made to validate-config, multiple assume role calls are done. Add method to
#    ,bcheck role expiry and avoid assuming role where possible

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

function usage() {
  if [ -n "$1" ]; then
    >&2 echo -e "ERROR: $1\n"
  fi
  >&2 echo "Usage: $0 --env-vars-file env_vars_file"
  >&2 echo ""
  >&2 echo "Example: $0 --env-vars-file /tmp/.last9.config.sh"
}

# parse params
while [[ "$#" -gt 0 ]]; do
  case $1 in
  --env-vars-file)
    env_vars_file="$2"
    shift
    shift
    ;;
  *)
    usage "Unknown parameter passed: $1"
    exit 1
    ;;
  esac
done

>&2 echo "STATUS: Validating config"

env_vars_file=${env_vars_file:-""}
if [[ "$env_vars_file" == "" ]]; then
  >&2 echo "ERROR: No value specified for --env-vars-file"
  exit 1
fi

if ! [[ -f $env_vars_file ]]; then
  >&2 echo "ERROR: env_vars_file=$env_vars_file does not exist"
  exit 1
fi

# shellcheck disable=1090
source "$env_vars_file"

LAST9_API_CONFIG_STR=${LAST9_API_CONFIG_STR:-""}
export LAST9_API_CONFIG_STR
if [[ "$LAST9_API_CONFIG_STR" == "" ]]; then
  >&2 echo "--------------------"
  >&2 echo "ERROR: Environment variable LAST9_API_CONFIG_STR not set. Check the pre-requisites section of this repo's README."
  >&2 echo "--------------------"
  exit 1
fi

iac_config_file="/tmp/.last9-iac.config.json"
if ! echo -e "$LAST9_API_CONFIG_STR" | jq >$iac_config_file; then
  >&2 echo "--------------------"
  >&2 echo "ERROR: Failed to parse environment variable LAST9_API_CONFIG_STR - invalid json"
  >&2 echo "--------------------"
  exit 1
fi
>&2 echo "STATUS: env_var=LAST9_API_CONFIG_STR status=valid"

LAST9_BACKUP_S3_BUCKET=${LAST9_BACKUP_S3_BUCKET:-""}
if [[ $LAST9_BACKUP_S3_BUCKET == "" ]]; then
  >&2 echo "--------------------"
  >&2 echo "ERROR: Environment variable LAST9_BACKUP_S3_BUCKET not set. Check the pre-requisites section of this repo's README."
  >&2 echo "--------------------"
  exit 1
fi

AWS_ASSUME_ROLE_ARN=${AWS_ASSUME_ROLE_ARN:-""}
AWS_ASSUME_ROLE_EXTERNAL_ID=${AWS_ASSUME_ROLE_EXTERNAL_ID:-""}
AWS_ASSUME_ROLE_DURATION_SEC=${AWS_ASSUME_ROLE_DURATION_SEC:-3600}

if [[ "$AWS_ASSUME_ROLE_ARN" != "" ]] && [[ "$AWS_ASSUME_ROLE_EXTERNAL_ID" != "" ]]; then

  # Env vars file exists - check if assume role entries are fresh enough to be reused
  reuse_creds=0
  if [[ -f $env_vars_file ]]; then
    # Do not use current credentials if they are expiring in 10 mins
    curr_timestamp=$(date +%s)
    set +e

    expiry_timestamp=$(\grep AWS_SESSION_EXPIRES_AT "$env_vars_file" | cut -f2 -d'=' | tr -d ' ' | cut -f1 -d'#')
    if [[ -z $expiry_timestamp ]]; then
      expiry_timestamp=0
    fi

    seconds_to_expire=$(echo "$expiry_timestamp - $curr_timestamp" | bc)
    refresh_before_sec=600

    set -e

    if [[ $seconds_to_expire -ge $refresh_before_sec ]]; then
      >&2 echo "STATUS: Current credentials expiring in $seconds_to_expire seconds >= $refresh_before_sec seconds. Reusing."
      reuse_creds=1
    else
      >&2 echo "STATUS: Current credentials expiring in $seconds_to_expire seconds <= $refresh_before_sec seconds. Reassuming."
    fi
  fi

  if [[ $reuse_creds -eq 0 ]]; then
    session_name="$(date +%s)_last9"
    >&2 echo "STATUS: using AWS_ASSUME_ROLE_ARN=$AWS_ASSUME_ROLE_ARN session=$session_name"

    # Delete assume role creds from env vars file and regenerate them
    sed -i '/# generated_by_assume_role/d' "$env_vars_file"
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN

    # shellcheck disable=1090
    source "$env_vars_file"

    >&2 echo "STATUS: Dumping old identity"
    aws sts get-caller-identity | jq -rc

    if ! aws sts assume-role --role-session-name "$session_name" --duration-seconds "$AWS_ASSUME_ROLE_DURATION_SEC" --role-arn "$AWS_ASSUME_ROLE_ARN" \
      --external-id "$AWS_ASSUME_ROLE_EXTERNAL_ID" | "$SCRIPT_DIR/assume-role-output-to-env.sh" >/tmp/assume-role-creds.sh 2>&1; then
      >&2 echo "ERROR: Failed to assume role $AWS_ASSUME_ROLE_ARN"
      exit 1
    fi

    # shellcheck disable=1091
    source "/tmp/assume-role-creds.sh"
    >&2 echo "STATUS: assumed role AWS_ASSUME_ROLE_ARN=$AWS_ASSUME_ROLE_ARN"

    export AWS_ASSUME_ROLE_ARN
    export AWS_ASSUME_ROLE_EXTERNAL_ID
    export AWS_ASSUME_ROLE_DURATION_SEC

    curr_timestamp=$(date +%s)
    expiry_timestamp=$(echo "$curr_timestamp + $AWS_ASSUME_ROLE_DURATION_SEC" | bc)
    {
      echo "export AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID' # generated_by_assume_role"
      echo "export AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY' # generated_by_assume_role"
      echo "export AWS_SESSION_TOKEN='$AWS_SESSION_TOKEN' # generated_by_assume_role"
      echo export AWS_SESSION_EXPIRES_AT="$expiry_timestamp # generated_by_assume_role"
    } >> "$env_vars_file"
  fi

  # shellcheck disable=1091
  source "/tmp/assume-role-creds.sh"
  >&2 echo "STATUS: Dumping new identity"

  aws sts get-caller-identity | jq -rc
fi

if ! aws s3 ls "$LAST9_BACKUP_S3_BUCKET" >/dev/null; then
  >&2 echo "--------------------"
  >&2 echo "ERROR: Failed to ls LAST9_BACKUP_S3_BUCKET=$LAST9_BACKUP_S3_BUCKET"
  >&2 echo "Please ensure that your AWS credentials have read/write access to $LAST9_BACKUP_S3_BUCKET"
  >&2 echo "--------------------"
  exit 1
fi
>&2 echo "STATUS: env_var=LAST9_BACKUP_S3_BUCKET status=valid"
>&2 echo "STATUS: action=check_aws_env_vars status=valid"

# shellcheck disable=2001
LAST9_BACKUP_S3_BUCKET=$(echo "$LAST9_BACKUP_S3_BUCKET" | sed 's:/*$::')
export LAST9_BACKUP_S3_BUCKET

# Check for pre-requisite commands
# shellcheck disable=SC2043
for cmd in python l9iac jq stat; do
  if ! command -v $cmd >/dev/null 2>&1; then
    >&2 echo "--------------------"
    >&2 echo "ERROR: Did not find command - $cmd. Check the pre-requisites section of this repo's README."
    >&2 echo "--------------------"
    exit 1
  fi
done
>&2 echo "STATUS: action=check_pre_req_commands status=valid"
