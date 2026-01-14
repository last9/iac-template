### Introduction

This repo contains scripts to manage Last9 alerts using Infrastructure as Code (IaC) principles. Alert YAML files are version-controlled in separate org-specific repositories and deployed via GitOps workflows.

## Repository Structure

```
workspace/
├── iac-template/              <- This repo (scripts and tooling)
│   ├── scripts/
│   │   ├── setup-iac-env.sh  <- Setup wizard
│   │   ├── fetch-alerts.py   <- Download alerts from Last9
│   │   └── run-iac.sh        <- Deploy alerts to Last9
│   └── .last9.config.json    <- Your configuration (gitignored)
└── <org>-alerts/              <- Your alerts repo (e.g., demo-alerts/)
    ├── alert1.yaml
    ├── alert2.yaml
    └── ...
```

## Quick Start

Get up and running in 10 minutes:

### 1. Run the Setup Script

From your `<org>-alerts` directory:

```bash
cd /path/to/<org>-alerts
../iac-template/scripts/setup-iac-env.sh
```

The interactive setup wizard will:
- ✅ Install dependencies (Python, jq, l9iac CLI)
- ✅ Collect your Last9 API tokens (get from https://app.last9.io/settings/api-tokens)
- ✅ Optionally configure AWS S3 for state locking
- ✅ Optionally configure GitHub Actions secrets

**All steps are optional** - you have full control. AWS S3 is only needed for distributed state locking in CI/CD environments. For local development, local state locking works fine.

### 2. Fetch Existing Alerts

From `iac-template` directory:

```bash
cd ../iac-template
python3 scripts/fetch-alerts.py
```

This will download your existing alerts from Last9 to `../<org>-alerts/` directory.

### 3. Review and Edit Alerts

```bash
cd ../<org>-alerts
ls *.yaml
vi <alert-name>.yaml  # Edit as needed
```

### 4. Test Locally

From `iac-template` directory:

```bash
cd ../iac-template
source env/bin/activate
./scripts/run-iac.sh --run-all-files --plan
```

### 5. Deploy Changes

From `<org>-alerts` directory:

```bash
cd ../<org>-alerts
git add *.yaml
git commit -m "Add/update alerts"
git push
```

GitHub Actions will automatically validate (plan) on PRs and deploy (apply) on merge to main.

---

## Detailed Workflow

### Managing Alerts

You can manage application and infra alerting by following these steps:

1. Create alert YAML files in your `<org>-alerts/` directory
2. Create a new branch for checking in changes
3. Raise a PR to the main branch
4. Last9 IaC will run a plan (similar to `terraform plan`) to validate the alert definitions
5. Review and merge the PR to main
6. Last9 IaC will run an apply action (similar to `terraform apply`) to deploy changes to Last9

**Note:** Alert templates are available in `templates/alerts/` directory for reference.

### GitHub Actions Setup & Required Secrets

To enable automated validation and deployment of alerting rules using GitHub Actions, configure the following repository secrets:

| Secret Name                  | Required | Description                                                                                 |
|------------------------------|----------|---------------------------------------------------------------------------------------------|
| LAST9_API_CONFIG_STR         | **Yes**  | JSON string with Last9 API config (see below for format)                                    |
| AWS_ACCESS_KEY_ID            | Optional | AWS access key for S3 state locking (recommended for production)                            |
| AWS_SECRET_ACCESS_KEY        | Optional | AWS secret key for S3 state locking                                                         |
| AWS_DEFAULT_REGION           | Optional | AWS region (e.g., us-east-1)                                                                |
| AWS_ASSUME_ROLE_ARN          | Optional | ARN of the AWS IAM role to assume (for cross-account or elevated access)                    |
| AWS_ASSUME_ROLE_EXTERNAL_ID  | Optional | External ID for the assumed role (if required by your AWS setup)                            |
| LAST9_BACKUP_S3_BUCKET       | Optional | S3 bucket for Last9 IaC state backup (required if using AWS S3 state locking)               |

**Note:** AWS secrets are optional. Without AWS configuration, the workflow will use local state locking. For single-user or development environments, local state locking is sufficient. For production with multiple team members or concurrent CI/CD runs, AWS S3 state locking is recommended to prevent conflicts.

**Quick Setup:** Run `./scripts/setup-iac-env.sh` to automatically configure these secrets using the GitHub CLI.

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
