### Introduction

This repo is used to manage alerts on Last9.

### Enabling alerting for application and infra metrics

You can manage application and infra alerting by following these steps:

1. Create a new branch for checking in changes.
2. Add relevant alerting yaml files in [./workspace/alerts/app](./workspace/alerts/app)
3. Raise a PR.
4. This will cause Last9 Infra-as-code (referred to IaC henceforth) to run a plan (similar to `terraform plan`) to do syntactic and semantic validation of the checked in files.
5. Review and merge the PR to main.
6. This will run an apply action (similar to `terraform apply`) to apply the changes and relevant alert groups will be updated on Last9.

### GitHub Actions Setup & Required Secrets

To enable automated validation and deployment of alerting rules using GitHub Actions, you must configure the following repository secrets:

| Secret Name                  | Required | Description                                                                                 |
|------------------------------|----------|---------------------------------------------------------------------------------------------|
| AWS_ACCESS_KEY_ID            | Yes      | AWS access key for programmatic access                                                      |
| AWS_SECRET_ACCESS_KEY        | Yes      | AWS secret key for programmatic access                                                      |
| AWS_DEFAULT_REGION           | Yes      | AWS region (e.g., us-east-1)                                                                |
| AWS_ASSUME_ROLE_ARN          | Yes*     | ARN of the AWS IAM role to assume (for cross-account or elevated access)                    |
| AWS_ASSUME_ROLE_EXTERNAL_ID  | Yes*     | External ID for the assumed role (if required by your AWS setup)                            |
| LAST9_BACKUP_S3_BUCKET       | Yes      | S3 bucket for Last9 IaC state backup                                                        |
| LAST9_API_CONFIG_STR         | Yes      | JSON string with Last9 API config (see below for format)                                    |

*Required if your workflow needs to assume a role for access. Otherwise, can be omitted if not using role assumption.

#### Example: `LAST9_API_CONFIG_STR`

```
cat > /tmp/.last9-iac.config.json

{
  "api_config": {
    "read": {
      "refresh_token": "xxx",
      "api_base_url": "https://app.last9.io/api/v4",
      "org": "<org>"
    },
    "write": {
      "refresh_token": "xxx",
      "api_base_url": "https://app.last9.io/api/v4",
      "org": "<org>"
    },
    "delete": {
      "refresh_token": "xxx",
      "api_base_url": "https://app.last9.io/api/v4",
      "org": "<org>"
    }
  },
  "state_lock_file_path": "./app.lock"
}
```

### CI Workflow Steps (Summary)

The GitHub Actions workflow (`.github/workflows/run_iac.yaml`) performs the following steps:

1. **Check out code**
2. **Set up Python 3.11 and create a virtual environment**
3. **Install IaC dependencies**
   - Runs `scripts/install_iac.sh` to download and install the latest Last9 IaC package and dependencies.
4. **Run IaC Plan**
   - Executes `scripts/run-iac.sh --run-all-files --plan` to validate alerting rules.
5. **Run IaC Apply (on main branch only)**
   - Executes `scripts/run-iac.sh --run-all-files --apply` to apply changes to Last9.

All steps require the above secrets to be set. The scripts will fail with clear error messages if any required secret is missing or invalid.

### Troubleshooting
- Ensure all required secrets are set in your repository settings under **Settings > Secrets and variables > Actions**.
- The `LAST9_API_CONFIG_STR` must be valid JSON. If you see errors about invalid JSON, double-check the format.
- AWS credentials must have permissions to access the specified S3 bucket and (if using) assume the specified role.
- For more details, check the logs of the failed GitHub Actions run.

#### About AWS Variables and S3 Bucket Usage

The following AWS-related secrets are required for the workflow:

- **AWS_ACCESS_KEY_ID** / **AWS_SECRET_ACCESS_KEY** / **AWS_DEFAULT_REGION**: These provide the necessary credentials and region for the workflow to access AWS resources.
- **AWS_ASSUME_ROLE_ARN** / **AWS_ASSUME_ROLE_EXTERNAL_ID**: Used to assume a specific AWS IAM role. **This role must have permissions to access the specified S3 bucket (`LAST9_BACKUP_S3_BUCKET`) for reading and writing state files, including `state.lock`.**
- **LAST9_BACKUP_S3_BUCKET**: This S3 bucket is used by the workflow to store and access the state files required for Last9 IaC operations. In particular, a `state.lock` file is created and managed in this bucket to ensure safe, consistent, and concurrent infrastructure changes. The workflow will read and write to this bucket as part of the plan and apply steps.

**Note:**
- The workflow requires read and write permissions to the specified S3 bucket.
- If the bucket or credentials are misconfigured, the workflow will fail with a clear error message.
