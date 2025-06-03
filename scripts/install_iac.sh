#!/bin/bash

RED='\033[1;31m'
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

install_iac() {
  # cleanup any previous installation
  pip3 uninstall -y pylast9 l9iac py_metricsql

  l9iac_download_url="https://d1pyat5h324sbq.cloudfront.net/stable/l9iac-latest.tar.gz"
  echo "STATUS: Downloading l9iac from $l9iac_download_url"
  wget $l9iac_download_url >/dev/null 2>/tmp/err.txt
  exit_status=$?
  if [ $exit_status -eq 0 ]; then
    >&2 echo "STATUS: Downloaded l9iac from $l9iac_download_url"
  else
    >&2 echo "ERROR: Failed to download l9iac - $iac_tar_file from CDN $l9iac_download_url"

  tar -xzvf "$iac_tar_file"
  pip3 install pylast9-*.whl
  bash scripts/setup_prerequisites.sh
  pip3 install dist/l9iac-*.whl

  # cleanup
  rm -rf pylast9-*.whl dist/l9iac-*.whl "$iac_tar_file" scripts/setup_prerequisites.sh
}

#### main ####

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
fi

iac_version=${1:-latest}
iac_tar_file="l9iac-${iac_version}.tar.gz"

install_iac
