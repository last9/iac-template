#!/bin/bash
# Last9 IaC Environment Setup Script
# Interactive wizard for setting up alerts-as-code environment
# All steps are optional - user has full control

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Track configuration state
LAST9_ORG=""
LAST9_API_BASE_URL="https://otlp-aps1.last9.io:443"
LAST9_READ_TOKEN=""
LAST9_WRITE_TOKEN=""
LAST9_DELETE_TOKEN=""
AWS_CONFIGURED=false
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_DEFAULT_REGION=""
LAST9_BACKUP_S3_BUCKET=""
AWS_ASSUME_ROLE_ARN=""
AWS_ASSUME_ROLE_EXTERNAL_ID=""
AWS_ASSUME_ROLE_DURATION_SEC=""
GH_ACTIONS_CONFIGURED=false
DEPS_INSTALLED=false
IN_GIT_REPO=false

# Utility functions
print_section_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}Step $1${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

print_separator() {
    echo -e "${CYAN}───────────────────────────────────────────────────────${NC}"
}

# Detect OS and architecture
detect_os() {
    OS_TYPE=$(uname -s)
    case "$OS_TYPE" in
        Darwin*)
            OS="macos"
            PKG_MANAGER="brew"
            ;;
        Linux*)
            OS="linux"
            # Detect Linux distribution
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                case "$ID" in
                    ubuntu|debian)
                        PKG_MANAGER="apt"
                        ;;
                    centos|rhel|fedora)
                        PKG_MANAGER="yum"
                        if command -v dnf &>/dev/null; then
                            PKG_MANAGER="dnf"
                        fi
                        ;;
                    *)
                        PKG_MANAGER="unknown"
                        ;;
                esac
            else
                PKG_MANAGER="unknown"
            fi
            ;;
        *)
            OS="unknown"
            PKG_MANAGER="unknown"
            ;;
    esac
}

# Check Python version
check_python() {
    print_step "1/9: Checking Prerequisites"

    # Check for Python 3.11+
    if command -v python3 &>/dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
        PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

        if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 11 ]; then
            print_success "Python $PYTHON_VERSION found"
            return 0
        else
            print_warning "Python $PYTHON_VERSION found, but 3.11+ required"
        fi
    else
        print_warning "Python 3 not found"
    fi

    # Offer to install Python
    echo ""
    read -rp "Install Python 3.11+? [y/N]: " install_python

    if [[ "$install_python" =~ ^[Yy]$ ]]; then
        install_python_for_os
    else
        print_info "Skipping Python installation"
        print_info "You can install Python manually from: https://www.python.org/downloads/"
        return 1
    fi
}

install_python_for_os() {
    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                print_info "Installing Python 3.11 via Homebrew..."
                brew install python@3.11
                print_success "Python installed"
            else
                print_error "Homebrew not found. Please install from: https://brew.sh/"
                return 1
            fi
            ;;
        linux)
            case "$PKG_MANAGER" in
                apt)
                    print_info "Installing Python 3.11..."
                    sudo apt-get update
                    sudo apt-get install -y python3.11 python3.11-venv python3-pip
                    print_success "Python installed"
                    ;;
                dnf|yum)
                    print_info "Installing Python 3.11..."
                    sudo $PKG_MANAGER install -y python3.11
                    print_success "Python installed"
                    ;;
                *)
                    print_error "Cannot auto-install Python on this system"
                    print_info "Please install Python 3.11+ manually"
                    return 1
                    ;;
            esac
            ;;
        *)
            print_error "Cannot auto-install Python on this OS"
            return 1
            ;;
    esac
}

# Check and install system dependencies
check_system_dependencies() {
    # Check jq
    if command -v jq &>/dev/null; then
        print_success "jq installed"
    else
        print_info "jq not found"
        read -rp "  Install jq for JSON processing? [Y/n]: " install_jq
        if [[ ! "$install_jq" =~ ^[Nn]$ ]]; then
            install_jq_for_os
        else
            print_warning "jq is required for configuration file generation"
        fi
    fi

    # Check git
    if command -v git &>/dev/null; then
        print_success "git installed"
    else
        print_warning "git not found - required for version control"
    fi

    # Check curl
    if command -v curl &>/dev/null; then
        print_success "curl installed"
    else
        print_info "curl not found"
        read -rp "  Install curl? [Y/n]: " install_curl
        if [[ ! "$install_curl" =~ ^[Nn]$ ]]; then
            install_curl_for_os
        fi
    fi
}

install_jq_for_os() {
    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                brew install jq
                print_success "jq installed"
            fi
            ;;
        linux)
            case "$PKG_MANAGER" in
                apt)
                    sudo apt-get install -y jq
                    print_success "jq installed"
                    ;;
                dnf|yum)
                    sudo $PKG_MANAGER install -y jq
                    print_success "jq installed"
                    ;;
            esac
            ;;
    esac
}

install_curl_for_os() {
    case "$OS" in
        linux)
            case "$PKG_MANAGER" in
                apt)
                    sudo apt-get install -y curl
                    print_success "curl installed"
                    ;;
                dnf|yum)
                    sudo $PKG_MANAGER install -y curl
                    print_success "curl installed"
                    ;;
            esac
            ;;
    esac
}

# Check AWS CLI (optional)
check_aws_cli() {
    echo ""
    if command -v aws &>/dev/null; then
        AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}')
        print_success "$AWS_VERSION installed"
        return 0
    else
        print_info "AWS CLI not found"
        echo "  AWS CLI is optional - needed only for S3 state locking"
        read -rp "  Install AWS CLI for S3 state locking? [y/N]: " install_aws

        if [[ "$install_aws" =~ ^[Yy]$ ]]; then
            install_aws_cli
            return $?
        else
            print_info "Skipping AWS CLI - will use local state locking"
            return 1
        fi
    fi
}

install_aws_cli() {
    print_info "Installing AWS CLI v2..."

    case "$OS" in
        macos)
            curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "/tmp/AWSCLIV2.pkg"
            sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
            rm /tmp/AWSCLIV2.pkg
            ;;
        linux)
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
            cd /tmp
            unzip -q awscliv2.zip
            sudo ./aws/install
            rm -rf aws awscliv2.zip
            cd - > /dev/null
            ;;
        *)
            print_error "Cannot auto-install AWS CLI on this OS"
            return 1
            ;;
    esac

    if command -v aws &>/dev/null; then
        print_success "AWS CLI installed"
        return 0
    else
        print_error "AWS CLI installation failed"
        return 1
    fi
}

# Check GitHub CLI (optional)
check_gh_cli() {
    echo ""
    if command -v gh &>/dev/null; then
        GH_VERSION=$(gh --version 2>&1 | head -1 | awk '{print $3}')
        print_success "GitHub CLI v$GH_VERSION installed"
        return 0
    else
        print_info "GitHub CLI not found"
        echo "  GitHub CLI is optional - needed for automated GitHub Actions setup"
        read -rp "  Install gh CLI for automated GitHub Actions setup? [y/N]: " install_gh

        if [[ "$install_gh" =~ ^[Yy]$ ]]; then
            install_gh_cli
            return $?
        else
            print_info "Skipping gh CLI - you can configure secrets manually"
            return 1
        fi
    fi
}

install_gh_cli() {
    print_info "Installing GitHub CLI..."

    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                brew install gh
            else
                print_error "Homebrew required to install gh CLI"
                return 1
            fi
            ;;
        linux)
            case "$PKG_MANAGER" in
                apt)
                    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                    sudo apt-get update
                    sudo apt-get install -y gh
                    ;;
                dnf|yum)
                    sudo $PKG_MANAGER install -y gh
                    ;;
                *)
                    print_error "Cannot auto-install gh CLI on this distribution"
                    return 1
                    ;;
            esac
            ;;
        *)
            print_error "Cannot auto-install gh CLI on this OS"
            return 1
            ;;
    esac

    if command -v gh &>/dev/null; then
        print_success "GitHub CLI installed"
        return 0
    else
        print_error "GitHub CLI installation failed"
        return 1
    fi
}

# Setup repository
setup_repository() {
    print_step "2/9: Repository Setup"

    # Check if already in a git repository
    if git rev-parse --git-dir &>/dev/null 2>&1; then
        IN_GIT_REPO=true
        REPO_ROOT=$(git rev-parse --show-toplevel)
        print_success "Already in git repository: $REPO_ROOT"

        read -rp "Continue with this repository? [Y/n]: " continue_repo
        if [[ "$continue_repo" =~ ^[Nn]$ ]]; then
            print_info "Please cd to your desired repository and run this script again"
            exit 0
        fi
    else
        print_info "Not in a git repository"
        echo ""
        echo "Options:"
        echo "  1) Use current directory (will initialize git if needed)"
        echo "  2) Provide path to existing local clone"
        echo "  3) Clone from GitHub URL"
        echo "  4) Skip (set up repository later)"
        echo ""
        read -rp "Choose option [1-4]: " repo_option

        case "$repo_option" in
            1)
                print_info "Using current directory: $REPO_ROOT"
                if [ ! -d "$REPO_ROOT/.git" ]; then
                    read -rp "Initialize git repository? [Y/n]: " init_git
                    if [[ ! "$init_git" =~ ^[Nn]$ ]]; then
                        git init
                        print_success "Git repository initialized"
                        IN_GIT_REPO=true
                    fi
                fi
                ;;
            2)
                read -rp "Enter path to local repository: " local_path
                if [ -d "$local_path" ]; then
                    cd "$local_path"
                    REPO_ROOT=$(pwd)
                    if git rev-parse --git-dir &>/dev/null 2>&1; then
                        IN_GIT_REPO=true
                        print_success "Using repository: $REPO_ROOT"
                    else
                        print_warning "Directory is not a git repository"
                    fi
                else
                    print_error "Directory not found: $local_path"
                    print_info "Continuing with current directory"
                fi
                ;;
            3)
                read -rp "Enter GitHub repository URL: " repo_url
                read -rp "Enter directory name (default: iac-alerts): " dir_name
                dir_name=${dir_name:-iac-alerts}

                print_info "Cloning repository..."
                if git clone "$repo_url" "$dir_name"; then
                    cd "$dir_name"
                    REPO_ROOT=$(pwd)
                    IN_GIT_REPO=true
                    print_success "Repository cloned: $REPO_ROOT"
                else
                    print_error "Failed to clone repository"
                    print_info "Continuing with current directory"
                fi
                ;;
            4)
                print_info "Skipping repository setup"
                ;;
            *)
                print_warning "Invalid option, using current directory"
                ;;
        esac
    fi
}

# Collect Last9 API configuration
collect_last9_config() {
    print_step "3/9: Last9 API Configuration (Required)"

    print_info "Obtain API tokens from: ${CYAN}https://app.last9.io/settings/api-tokens${NC}"
    echo ""
    echo "You need three types of refresh tokens:"
    echo "  - Read token: For fetching existing alerts"
    echo "  - Write token: For creating/updating alerts"
    echo "  - Delete token: For removing alerts"
    echo ""

    read -rp "Organization slug: " LAST9_ORG
    read -rp "API Base URL [${LAST9_API_BASE_URL}]: " api_url_input
    if [ -n "$api_url_input" ]; then
        LAST9_API_BASE_URL="$api_url_input"
    fi

    echo ""
    read -rsp "Read refresh token: " LAST9_READ_TOKEN
    echo ""
    read -rsp "Write refresh token: " LAST9_WRITE_TOKEN
    echo ""
    read -rsp "Delete refresh token: " LAST9_DELETE_TOKEN
    echo ""

    # Mask tokens for display
    READ_MASKED="****${LAST9_READ_TOKEN: -4}"
    WRITE_MASKED="****${LAST9_WRITE_TOKEN: -4}"
    DELETE_MASKED="****${LAST9_DELETE_TOKEN: -4}"

    echo ""
    print_success "API configuration collected"
    print_info "Organization: $LAST9_ORG"
    print_info "Read token: $READ_MASKED"
    print_info "Write token: $WRITE_MASKED"
    print_info "Delete token: $DELETE_MASKED"
}

# Setup alerts directory
setup_alerts_directory() {
    print_step "4/9: Alerts Directory Setup"

    # Determine parent directory (one level up from iac-template)
    PARENT_DIR=$(dirname "$REPO_ROOT")
    ALERTS_DIR="$PARENT_DIR/${LAST9_ORG}-alerts"

    echo "This will create the alerts directory: $ALERTS_DIR"
    read -rp "Create ${LAST9_ORG}-alerts directory? [Y/n]: " create_alerts_dir

    if [[ "$create_alerts_dir" =~ ^[Nn]$ ]]; then
        print_info "Skipping alerts directory creation"
        print_info "You can create it manually later: mkdir ../${LAST9_ORG}-alerts"
        return 0
    fi

    # Create alerts directory
    if [ -d "$ALERTS_DIR" ]; then
        print_success "Directory already exists: $ALERTS_DIR"
    else
        mkdir -p "$ALERTS_DIR"
        print_success "Created directory: $ALERTS_DIR"
    fi

    # Initialize git repo if needed
    if [ ! -d "$ALERTS_DIR/.git" ]; then
        read -rp "Initialize git repository in ${LAST9_ORG}-alerts? [Y/n]: " init_alerts_git
        if [[ ! "$init_alerts_git" =~ ^[Nn]$ ]]; then
            cd "$ALERTS_DIR"
            git init
            print_success "Initialized git repository"

            # Create .gitignore
            cat > .gitignore <<'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
*.egg-info/

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Locks
*.lock
*.lock.bak
EOF
            print_success "Created .gitignore"

            # Create README
            cat > README.md <<EOF
# ${LAST9_ORG} Alerts

This repository contains alert definitions for ${LAST9_ORG}, managed using Last9 Infrastructure as Code (IaC).

## Directory Structure

- \`*.yaml\` - Alert definition files
- Adjacent \`iac-template/\` directory contains scripts and tooling

## Workflow

1. Edit alert YAML files in this directory
2. Test locally (Linux) or validate via GitHub Actions (macOS)
3. Commit and push changes
4. GitHub Actions will automatically deploy to Last9

## Quick Commands

Fetch existing alerts from Last9:
\`\`\`bash
cd ../iac-template
python3 scripts/fetch-alerts.py
\`\`\`

Test alerts locally (Linux only):
\`\`\`bash
cd ../iac-template
source env/bin/activate
./scripts/run-iac.sh --run-all-files --plan
\`\`\`

Deploy via GitHub Actions:
\`\`\`bash
git add *.yaml
git commit -m "Update alerts"
git push
\`\`\`

For more information, see \`../iac-template/README.md\`
EOF
            print_success "Created README.md"

            cd "$REPO_ROOT"
        fi
    else
        print_success "Git repository already initialized"
    fi

    print_success "Alerts directory ready: $ALERTS_DIR"
}

# Main execution
main() {
    print_section_header "Last9 Infrastructure as Code - Setup Wizard"
    echo -e "${CYAN}(All steps are optional - you have full control)${NC}"

    # Detect OS
    detect_os

    # Check prerequisites
    check_python || true
    check_system_dependencies
    check_aws_cli && AWS_CLI_AVAILABLE=true || AWS_CLI_AVAILABLE=false
    check_gh_cli && GH_CLI_AVAILABLE=true || GH_CLI_AVAILABLE=false

    # Setup repository
    setup_repository

    # Collect Last9 configuration (required)
    collect_last9_config

    # Setup alerts directory
    setup_alerts_directory

    # Collect AWS configuration (optional)
    collect_aws_config

    # Generate configuration file
    generate_config_file

    # Install dependencies
    install_dependencies

    # Configure GitHub Actions (optional)
    configure_github_actions

    # Validate setup
    validate_setup

    # Print summary
    print_summary
}

# Collect AWS configuration (optional)
collect_aws_config() {
    print_step "5/9: AWS Configuration (Optional)"

    echo "AWS S3 state locking prevents concurrent modifications in CI/CD"
    echo "You can skip this and use local state locking for now"
    echo ""
    read -rp "Configure AWS S3 for state locking? [y/N]: " configure_aws

    if [[ ! "$configure_aws" =~ ^[Yy]$ ]]; then
        print_info "Using local state locking (./app.lock)"
        print_info "You can add AWS configuration later if needed"
        AWS_CONFIGURED=false
        return 0
    fi

    # Check if AWS CLI is configured
    if command -v aws &>/dev/null && aws sts get-caller-identity &>/dev/null 2>&1; then
        print_success "AWS CLI is already configured"
        read -rp "Use existing AWS credentials? [Y/n]: " use_existing

        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            # Extract from AWS CLI config
            AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id || echo "")
            AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key || echo "")
            AWS_DEFAULT_REGION=$(aws configure get region || echo "us-east-1")
        else
            prompt_aws_credentials
        fi
    else
        prompt_aws_credentials
    fi

    # Prompt for S3 bucket
    echo ""
    read -rp "S3 bucket for state backup (e.g., my-iac-state): " s3_input
    if [[ "$s3_input" =~ ^s3:// ]]; then
        LAST9_BACKUP_S3_BUCKET="$s3_input"
    else
        LAST9_BACKUP_S3_BUCKET="s3://$s3_input"
    fi

    # Test S3 access
    print_info "Testing S3 bucket access..."
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

    if aws s3 ls "$LAST9_BACKUP_S3_BUCKET" &>/dev/null; then
        print_success "S3 bucket is accessible"
        AWS_CONFIGURED=true
    else
        print_error "Cannot access S3 bucket"
        print_warning "Check permissions or bucket name"
        read -rp "Continue without AWS S3? [Y/n]: " skip_aws
        if [[ "$skip_aws" =~ ^[Nn]$ ]]; then
            exit 1
        fi
        AWS_CONFIGURED=false
    fi

    # Optional: Assume role configuration
    echo ""
    read -rp "Do you need to assume an IAM role? [y/N]: " need_assume_role
    if [[ "$need_assume_role" =~ ^[Yy]$ ]]; then
        read -rp "Role ARN: " AWS_ASSUME_ROLE_ARN
        read -rp "External ID (optional): " AWS_ASSUME_ROLE_EXTERNAL_ID
        read -rp "Duration (seconds, default 3600): " AWS_ASSUME_ROLE_DURATION_SEC
        AWS_ASSUME_ROLE_DURATION_SEC=${AWS_ASSUME_ROLE_DURATION_SEC:-3600}
    fi
}

prompt_aws_credentials() {
    echo ""
    read -rp "AWS Access Key ID: " AWS_ACCESS_KEY_ID
    read -rsp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
    read -rp "AWS Region (default: us-east-1): " AWS_DEFAULT_REGION
    AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
}

# Generate configuration file
generate_config_file() {
    print_step "6/9: Configuration File"

    config_file="$REPO_ROOT/.last9.config.json"

    # Build iac_config section
    iac_config=$(cat <<EOF
{
  "api_config": {
    "read": {
      "refresh_token": "$LAST9_READ_TOKEN",
      "api_base_url": "$LAST9_API_BASE_URL",
      "org": "$LAST9_ORG"
    },
    "write": {
      "refresh_token": "$LAST9_WRITE_TOKEN",
      "api_base_url": "$LAST9_API_BASE_URL",
      "org": "$LAST9_ORG"
    },
    "delete": {
      "refresh_token": "$LAST9_DELETE_TOKEN",
      "api_base_url": "$LAST9_API_BASE_URL",
      "org": "$LAST9_ORG"
    }
  },
  "state_lock_file_path": "./app.lock"
}
EOF
)

    # Build complete config
    if [ "$AWS_CONFIGURED" = true ]; then
        # Include AWS configuration
        cat > "$config_file" <<EOF
{
  "aws_access_key_id": "$AWS_ACCESS_KEY_ID",
  "aws_secret_access_key": "$AWS_SECRET_ACCESS_KEY",
  "aws_default_region": "$AWS_DEFAULT_REGION",
  "last9_backup_s3_bucket": "$LAST9_BACKUP_S3_BUCKET",
  "iac_config": $iac_config
}
EOF

        # Add assume role fields if configured
        if [ -n "$AWS_ASSUME_ROLE_ARN" ]; then
            tmp_file=$(mktemp)
            jq --arg arn "$AWS_ASSUME_ROLE_ARN" \
               --arg extid "${AWS_ASSUME_ROLE_EXTERNAL_ID:-}" \
               --arg dur "${AWS_ASSUME_ROLE_DURATION_SEC:-3600}" \
               '. + {
                 "aws_assume_role_arn": $arn,
                 "aws_assume_role_external_id": $extid,
                 "aws_assume_role_duration_sec": ($dur | tonumber)
               }' "$config_file" > "$tmp_file"
            mv "$tmp_file" "$config_file"
        fi
    else
        # Last9 API only
        cat > "$config_file" <<EOF
{
  "iac_config": $iac_config
}
EOF
    fi

    # Validate JSON
    if ! jq . "$config_file" >/dev/null 2>&1; then
        print_error "Invalid JSON in configuration file"
        exit 1
    fi

    print_success "Created .last9.config.json"

    # Set secure permissions
    chmod 600 "$config_file"
    print_success "Set secure permissions (600)"

    # Add to .gitignore if in git repo
    if [ "$IN_GIT_REPO" = true ]; then
        if [ -f "$REPO_ROOT/.gitignore" ]; then
            if ! grep -q "^\.last9\.config\.json$" "$REPO_ROOT/.gitignore" 2>/dev/null; then
                echo ".last9.config.json" >> "$REPO_ROOT/.gitignore"
                print_success "Added to .gitignore"
            fi
        else
            echo ".last9.config.json" > "$REPO_ROOT/.gitignore"
            print_success "Created .gitignore and added config file"
        fi
    fi
}

# Install dependencies
install_dependencies() {
    print_step "7/9: Install Dependencies"

    # Detect OS
    OS_TYPE=$(uname -s)
    if [[ "$OS_TYPE" == "Darwin"* ]]; then
        echo ""
        print_warning "⚠️  macOS Limitation Detected"
        echo ""
        echo "l9iac CLI has known compatibility issues on macOS due to:"
        echo "  - py-metricsql dependency can't be built natively"
        echo "  - Bundled Go binaries are for Linux only"
        echo ""
        echo "Recommendation:"
        echo "  ✓ Skip local l9iac installation"
        echo "  ✓ Use GitHub Actions for validation and deployment"
        echo "  ✓ You can still fetch and edit alerts locally"
        echo ""
        read -rp "Install l9iac anyway (may not work)? [y/N]: " install_deps

        if [[ ! "$install_deps" =~ ^[Yy]$ ]]; then
            print_info "Skipping l9iac installation (recommended for macOS)"
            print_info "You can still:"
            print_info "  ✓ Fetch alerts: python3 scripts/fetch-alerts.py"
            print_info "  ✓ Edit alerts in ${LAST9_ORG}-alerts/"
            print_info "  ✓ Use GitHub Actions for validation/deployment"
            DEPS_INSTALLED=false
            return 0
        fi
    else
        read -rp "Install l9iac CLI and Python dependencies? [Y/n]: " install_deps
        if [[ "$install_deps" =~ ^[Nn]$ ]]; then
            print_info "Skipping dependency installation"
            DEPS_INSTALLED=false
            return 0
        fi
    fi

    # Check Python version
    if command -v python3.11 &>/dev/null; then
        PYTHON_CMD="python3.11"
        print_success "Using Python 3.11"
    elif command -v python3 &>/dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
        PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

        if [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -ge 11 ] && [ "$PYTHON_MINOR" -le 12 ]; then
            PYTHON_CMD="python3"
            print_success "Using Python $PYTHON_VERSION"
        else
            print_error "l9iac requires Python 3.11 or 3.12 (you have $PYTHON_VERSION)"
            print_info "Install Python 3.11: brew install python@3.11"
            DEPS_INSTALLED=false
            return 1
        fi
    else
        print_error "Python 3.11 or 3.12 not found"
        print_info "Install Python 3.11: brew install python@3.11"
        DEPS_INSTALLED=false
        return 1
    fi

    # Create Python virtual environment
    if [ ! -d "$REPO_ROOT/env" ]; then
        print_info "Creating Python virtual environment with $PYTHON_CMD..."
        $PYTHON_CMD -m venv "$REPO_ROOT/env"
        print_success "Created virtual environment"
    else
        print_success "Virtual environment already exists"
    fi

    # Activate virtual environment
    source "$REPO_ROOT/env/bin/activate"

    # Run install_iac.sh
    if [ -f "$SCRIPT_DIR/install_iac.sh" ]; then
        print_info "Installing l9iac CLI..."
        if bash "$SCRIPT_DIR/install_iac.sh"; then
            print_success "l9iac package installed"
        else
            print_error "Failed to install l9iac CLI"
            return 1
        fi
    else
        print_error "install_iac.sh not found"
        return 1
    fi

    # Verify installation
    if l9iac --version &>/dev/null 2>&1; then
        version=$(l9iac --version 2>&1)
        print_success "l9iac is functional: $version"
        DEPS_INSTALLED=true
    else
        print_warning "l9iac installed but may not work due to missing dependencies"
        print_info "This is expected on macOS - use GitHub Actions for validation"
        DEPS_INSTALLED=false
    fi
}

# Configure GitHub Actions
configure_github_actions() {
    print_step "8/9: GitHub Actions Setup"

    read -rp "Configure GitHub Actions secrets? [y/N]: " setup_gh_actions

    if [[ ! "$setup_gh_actions" =~ ^[Yy]$ ]]; then
        print_info "Skipping GitHub Actions setup"
        print_info "You can configure secrets manually later in GitHub UI"
        GH_ACTIONS_CONFIGURED=false
        return 0
    fi

    # Check for gh CLI
    if ! command -v gh &>/dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        print_info "Install from: https://cli.github.com/"
        GH_ACTIONS_CONFIGURED=false
        return 1
    fi

    # Check if in git repo with remote
    if ! git remote get-url origin &>/dev/null 2>&1; then
        print_error "No git remote found. Cannot configure GitHub Actions."
        print_info "Add a remote first: git remote add origin <url>"
        GH_ACTIONS_CONFIGURED=false
        return 1
    fi

    # Authenticate gh CLI if needed
    if ! gh auth status &>/dev/null 2>&1; then
        print_info "Authenticating with GitHub..."
        gh auth login
    fi

    print_info "Setting GitHub Actions secrets..."

    # Set Last9 API config (always required)
    LAST9_API_CONFIG_STR=$(jq -c '.iac_config' "$REPO_ROOT/.last9.config.json")
    echo "$LAST9_API_CONFIG_STR" | gh secret set LAST9_API_CONFIG_STR 2>/dev/null || true

    # Set AWS secrets if configured
    if [ "$AWS_CONFIGURED" = true ]; then
        echo "$AWS_ACCESS_KEY_ID" | gh secret set AWS_ACCESS_KEY_ID 2>/dev/null || true
        echo "$AWS_SECRET_ACCESS_KEY" | gh secret set AWS_SECRET_ACCESS_KEY 2>/dev/null || true
        echo "$AWS_DEFAULT_REGION" | gh secret set AWS_DEFAULT_REGION 2>/dev/null || true
        echo "$LAST9_BACKUP_S3_BUCKET" | gh secret set LAST9_BACKUP_S3_BUCKET 2>/dev/null || true

        if [ -n "$AWS_ASSUME_ROLE_ARN" ]; then
            echo "$AWS_ASSUME_ROLE_ARN" | gh secret set AWS_ASSUME_ROLE_ARN 2>/dev/null || true
            [ -n "$AWS_ASSUME_ROLE_EXTERNAL_ID" ] && echo "$AWS_ASSUME_ROLE_EXTERNAL_ID" | gh secret set AWS_ASSUME_ROLE_EXTERNAL_ID 2>/dev/null || true
        fi
    fi

    print_success "GitHub Actions secrets configured"
    GH_ACTIONS_CONFIGURED=true
}

# Validate setup
validate_setup() {
    print_step "9/9: Validation"

    read -rp "Validate configuration now? [Y/n]: " run_validation

    if [[ "$run_validation" =~ ^[Nn]$ ]]; then
        print_info "Skipping validation"
        return 0
    fi

    # Test l9iac if installed
    if [ "$DEPS_INSTALLED" = true ]; then
        if command -v l9iac &>/dev/null; then
            print_success "l9iac CLI is functional"
        else
            print_warning "l9iac CLI not found in PATH"
        fi
    fi

    # Test S3 access if AWS configured
    if [ "$AWS_CONFIGURED" = true ]; then
        if aws s3 ls "$LAST9_BACKUP_S3_BUCKET" &>/dev/null 2>&1; then
            print_success "S3 bucket is accessible"
        else
            print_warning "S3 bucket access test failed"
        fi
    fi

    print_success "Configuration is valid"
}

# Print summary
print_summary() {
    print_section_header "Setup Complete! ✓"

    # Show what was configured
    print_success "Configuration: .last9.config.json ($([ "$AWS_CONFIGURED" = true ] && echo "Last9 + AWS" || echo "Last9 API only"))"

    # Show alerts directory if it exists
    PARENT_DIR=$(dirname "$REPO_ROOT")
    ALERTS_DIR="$PARENT_DIR/${LAST9_ORG}-alerts"
    if [ -d "$ALERTS_DIR" ]; then
        print_success "Alerts directory: $ALERTS_DIR"
    fi

    if [ "$DEPS_INSTALLED" = true ]; then
        print_success "Dependencies installed"
    fi

    if [ "$GH_ACTIONS_CONFIGURED" = true ]; then
        print_success "GitHub Actions secrets configured"
    else
        print_info "GitHub Actions: Configure manually"
    fi

    # Next steps
    print_separator
    echo -e "${BLUE}Next Steps:${NC}"
    print_separator
    echo ""
    echo "1. Fetch existing alerts from your Last9 tenant:"
    echo "   $ python3 scripts/fetch-alerts.py"
    echo ""
    echo "2. Review fetched alerts:"
    echo "   $ cd ../${LAST9_ORG}-alerts"
    echo "   $ ls *.yaml"
    echo ""
    echo "3. Edit alerts as needed (in the ${LAST9_ORG}-alerts directory)"
    echo ""

    # Show different workflow for macOS vs Linux
    OS_TYPE=$(uname -s)
    if [[ "$OS_TYPE" == "Darwin"* ]]; then
        echo "4. Validate via GitHub Actions (macOS can't run l9iac locally):"
        echo "   $ git add *.yaml"
        echo "   $ git checkout -b my-alert-changes"
        echo "   $ git commit -m \"Add/update alerts\""
        echo "   $ git push -u origin my-alert-changes"
        echo "   $ # Open PR and GitHub Actions will validate"
    else
        echo "4. Test alerts locally:"
        if [ "$DEPS_INSTALLED" = true ]; then
            echo "   $ cd ../iac-template"
            echo "   $ source env/bin/activate"
            echo "   $ ./scripts/run-iac.sh --run-all-files --plan"
        else
            echo "   $ # Install l9iac first, then run plan"
        fi
        echo ""
        echo "5. When ready, commit and push:"
        echo "   $ cd ../${LAST9_ORG}-alerts"
        echo "   $ git add *.yaml"
        echo "   $ git commit -m \"Add/update alerts\""
        echo "   $ git push"
    fi
    echo ""

    print_separator
    print_warning "Important: .last9.config.json contains sensitive data"
    print_warning "Never commit this file to version control!"

    if [ "$AWS_CONFIGURED" = false ]; then
        echo ""
        print_info "Tip: To add AWS S3 state locking later, edit .last9.config.json"
        print_info "and add aws_access_key_id, aws_secret_access_key, aws_default_region,"
        print_info "and last9_backup_s3_bucket fields."
    fi

    echo ""
}

# Run main function
main "$@"
