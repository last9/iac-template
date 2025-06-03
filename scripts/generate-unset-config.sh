#!/bin/bash

output_file="/tmp/.last9.config.unset.sh"
echo -n > $output_file

if [[ -n $LAST9_API_CONFIG_STR ]]; then
  echo unset LAST9_API_CONFIG_STR > $output_file
fi

if [[ -n $LAST9_BACKUP_S3_BUCKET ]]; then
  echo unset LAST9_BACKUP_S3_BUCKET >> $output_file
fi

if [[ -n $AWS_ACCESS_KEY_ID ]]; then
  echo unset AWS_ACCESS_KEY_ID >> $output_file
fi

if [[ -n $AWS_SECRET_ACCESS_KEY ]]; then
  echo unset AWS_SECRET_ACCESS_KEY >> $output_file
fi

if [[ -n $AWS_DEFAULT_REGION ]]; then
  echo unset AWS_DEFAULT_REGION >> $output_file
fi

if [[ -n $AWS_ASSUME_ROLE_ARN ]]; then
  echo unset AWS_ASSUME_ROLE_ARN >> $output_file
fi

if [[ -n $AWS_ASSUME_ROLE_EXTERNAL_ID ]]; then
  echo unset AWS_ASSUME_ROLE_EXTERNAL_ID >> $output_file
fi

if [[ -n $AWS_ASSUME_ROLE_DURATION_SEC ]]; then
  echo unset AWS_ASSUME_ROLE_DURATION_SEC >> $output_file
fi
