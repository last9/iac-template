#!/bin/bash

RED='\033[1;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
  echo "Usage: "
  echo -e "./$(basename $0) [IAC_VERSION]\n"
  echo "Arguments:"
  echo -e "\tIAC_VERSION - version of the IAC package to install. Defaults to 'latest'\n"
  exit 1
}

print_error() {
  echo -e "${RED}$1${NC}"
}

print_success() {
  echo -e "${GREEN}$1${NC}"
}

print_warning() {
  echo -e "${YELLOW}$1${NC}"
}

# Detect OS
detect_os() {
  OS_TYPE=$(uname -s)
  case "$OS_TYPE" in
    Darwin*)
      OS="macos"
      ;;
    Linux*)
      OS="linux"
      ;;
    *)
      OS="unknown"
      ;;
  esac
}

# Install Go on macOS if needed
ensure_go_macos() {
  if command -v go &>/dev/null; then
    print_success "Go is already installed: $(go version)"
    return 0
  fi

  print_warning "Go is not installed. Installing via Homebrew..."

  if command -v brew &>/dev/null; then
    brew install go
    if [ $? -eq 0 ]; then
      print_success "Go installed successfully"
      return 0
    else
      print_error "Failed to install Go via Homebrew"
      return 1
    fi
  else
    print_error "Homebrew not found. Please install Go manually from: https://go.dev/dl/"
    return 1
  fi
}

# Patch setup_prerequisites.sh to use system Go on macOS
patch_setup_prerequisites() {
  if [ ! -f scripts/setup_prerequisites.sh ]; then
    print_warning "setup_prerequisites.sh not found, skipping"
    return 0
  fi

  print_warning "Patching setup_prerequisites.sh for macOS compatibility..."

  # Create a patched version that uses system Go
  cat > scripts/setup_prerequisites.sh.patched << 'EOF'
#!/bin/bash
set -e

# Use system Go instead of bundled Go
if command -v go &>/dev/null; then
  export GOROOT=$(go env GOROOT)
  export GOPATH=$(go env GOPATH)
  export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
  echo "Using system Go: $(go version)"
else
  echo "ERROR: Go not found in system PATH"
  exit 1
fi

# Check if metricsql directory exists
if [ ! -d "metricsql" ]; then
  echo "Cloning metricsql repository..."
  git clone https://github.com/VictoriaMetrics/metricsql.git 2>/dev/null || echo "Already cloned"
fi

cd metricsql

# Try to build py_metricsql
echo "Building py_metricsql..."
if command -v gopy &>/dev/null; then
  gopy build -output=../py_metricsql .
else
  echo "WARNING: gopy not found, installing..."
  go install github.com/go-python/gopy@latest
  $GOPATH/bin/gopy build -output=../py_metricsql .
fi

cd ..

# Build wheel if successful
if [ -d "py_metricsql" ]; then
  cd py_metricsql
  python3 setup.py bdist_wheel
  cd ..
  echo "py_metricsql built successfully"
else
  echo "WARNING: py_metricsql build failed, continuing without it"
fi
EOF

  chmod +x scripts/setup_prerequisites.sh.patched
  mv scripts/setup_prerequisites.sh.patched scripts/setup_prerequisites.sh
}

install_iac() {
  detect_os

  # cleanup any previous installation
  pip3 uninstall -y pylast9 l9iac py_metricsql 2>/dev/null || true

  l9iac_download_url="https://d1pyat5h324sbq.cloudfront.net/stable/l9iac-latest.tar.gz"
  echo "STATUS: Downloading l9iac from $l9iac_download_url"
  wget $l9iac_download_url >/dev/null 2>/tmp/err.txt
  exit_status=$?
  if [ $exit_status -eq 0 ]; then
    >&2 echo "STATUS: Downloaded l9iac from $l9iac_download_url"
  else
    >&2 echo "ERROR: Failed to download l9iac - $iac_tar_file from CDN $l9iac_download_url"
    return 1
  fi

  echo "STATUS: Extracting l9iac package..."
  tar -xzf "$iac_tar_file" 2>/dev/null

  # Install pylast9 first
  if [ -f pylast9-*.whl ]; then
    echo "STATUS: Installing pylast9..."
    pip3 install pylast9-*.whl
  fi

  # Handle macOS-specific setup
  if [ "$OS" = "macos" ]; then
    print_warning "Detected macOS - applying compatibility patches..."

    # Remove bundled Go binaries (they're for Linux)
    if [ -d "go" ]; then
      echo "Removing incompatible bundled Go binaries..."
      rm -rf go
    fi

    # Ensure Go is installed on system
    if ! ensure_go_macos; then
      print_warning "Skipping py_metricsql build (Go not available)"
      # Continue without py_metricsql
    else
      # Patch the setup script to use system Go
      patch_setup_prerequisites

      # Try to run setup_prerequisites.sh
      if [ -f scripts/setup_prerequisites.sh ]; then
        echo "STATUS: Building prerequisites..."
        bash scripts/setup_prerequisites.sh 2>&1 || {
          print_warning "Prerequisites build failed, continuing without py_metricsql"
        }
      fi
    fi
  else
    # Linux - use original script
    if [ -f scripts/setup_prerequisites.sh ]; then
      bash scripts/setup_prerequisites.sh
    fi
  fi

  # Install l9iac wheel
  if [ -f dist/l9iac-*.whl ]; then
    echo "STATUS: Installing l9iac..."
    pip3 install dist/l9iac-*.whl
    print_success "l9iac installed successfully"
  else
    print_error "l9iac wheel not found"
    return 1
  fi

  # Verify installation
  if command -v l9iac &>/dev/null; then
    print_success "Installation verified: $(l9iac --version 2>&1 || echo 'l9iac installed')"
  else
    print_warning "l9iac command not found in PATH, but package may be installed"
  fi

  # cleanup
  echo "STATUS: Cleaning up temporary files..."
  rm -rf pylast9-*.whl dist/l9iac-*.whl "$iac_tar_file" scripts/setup_prerequisites.sh metricsql py_metricsql go 2>/dev/null

  print_success "Installation complete!"
}

#### main ####

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
fi

iac_version=${1:-latest}
iac_tar_file="l9iac-${iac_version}.tar.gz"

install_iac
