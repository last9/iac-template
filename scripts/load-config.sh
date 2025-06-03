#!/bin/bash

set -eou pipefail

function usage() {
  if [ -n "$1" ]; then
    >&2 echo -e "ERROR: $1\n"
  fi
  >&2 echo "Usage: $0 --config-file config_file --output-file output_file"
  >&2 echo "  ---config-file config file"
  >&2 echo "  ---output-file output file"
  >&2 echo ""
  >&2 echo "Example: $0 --config-file .last9.config.json --output-file /tmp/.last9.config.sh"
}

# parse params
while [[ "$#" -gt 0 ]]; do
  case $1 in
  --config-file)
    config_file="$2"
    shift
    shift
    ;;
  --output-file)
    output_file="$2"
    shift
    shift
    ;;
  --cache-config)
    cache_config="1"
    shift
    ;;
  *)
    usage "Unknown parameter passed: $1"
    exit 1
    ;;
  esac
done

cache_config=${cache_config:-"0"}

if [[ "$cache_config" == "1" ]] && [[ -f "$output_file" ]]; then
  >&2 echo "STATUS: Using cached config in $output_file"
  exit 0
fi

>&2 echo "STATUS: Loading config"

output_file=${output_file:-""}
if [[ $output_file == "" ]]; then
  >&2 echo "ERROR: Empty value specified for --output-file"
  exit 1
fi

output_dir=$(dirname "$output_file")
if ! [[ -d $output_dir ]]; then
  >&2 echo "ERROR: output_dir=$output_dir does not exist"
  exit 1
fi

if [[ -f "$output_file" ]]; then
  >&2 echo "STATUS: creating output_file=$output_file"
  rm "$output_file"
fi

config_file=${config_file:-""}
touch "$output_file"
if [[ $config_file == "" ]]; then
  >&2 echo "STATUS: Empty value specified for --config-file - using env vars"
  set +e
  for key in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION LAST9_BACKUP_S3_BUCKET LAST9_API_CONFIG_STR \
             AWS_ASSUME_ROLE_ARN AWS_ASSUME_ROLE_EXTERNAL_ID AWS_ASSUME_ROLE_DURATION_SEC; do
    value=$(env | grep -i "$key=" | cut -f2 -d'=')
    if [[ $value != "" ]]; then
      echo -e "export $key='$value'" >> "$output_file"
    fi
  done
  set -e
  exit 0
fi

if ! [[ -f $config_file ]]; then
  >&2 echo "ERROR: config_file=$config_file does not exist"
  exit 1
fi

if ! jq <"$config_file" >/dev/null; then
  >&2 echo "ERROR: config_file=$config_file - invalid json"
  exit 1
fi

for mandatory_key in aws_access_key_id aws_secret_access_key aws_default_region last9_backup_s3_bucket; do
  value=$(jq -r ".$mandatory_key" <"$config_file")
  if [[ "$value" == "null" ]] || [[ "$value" == "" ]]; then
    >&2 echo "ERROR: config_file=$config_file - $mandatory_key not specified"
    exit 1
  fi
  echo "export $(echo $mandatory_key | tr '[:lower:]' '[:upper:]')='$value'" >> "$output_file"
done

for optional_key in aws_assume_role_arn aws_assume_role_external_id aws_assume_role_duration_sec; do
  value=$(jq -r ".$optional_key" <"$config_file")
  if [[ "$value" != "null" ]] && [[ "$value" != "" ]]; then
    echo "export $(echo $optional_key | tr '[:lower:]' '[:upper:]')='$value'" >> "$output_file"
  fi
done

LAST9_API_CONFIG_STR=$(jq -c '.iac_config' <"$config_file")
if [[ "$LAST9_API_CONFIG_STR" == "null" ]]; then
  >&2 echo "ERROR: config_file=$config_file - $mandatory_key not specified"
  exit 1
fi

echo "export LAST9_API_CONFIG_STR='$LAST9_API_CONFIG_STR'" >> "$output_file"
