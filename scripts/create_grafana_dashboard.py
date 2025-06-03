#!/usr/bin/env python

"""Create Grafana dashboard from input payload"""

import os
import sys
import json
import argparse
import logging
from urllib.parse import urlparse
import requests


def load_args():
    """Parse cli"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-file", help="Grafana dashboard json payload file", required=True)
    parser.add_argument(
        "--api-config-str",
        help="Last9 API config string",
        required=False,
        default=os.environ.get('LAST9_API_CONFIG_STR', ''),
    )
    parser.add_argument("--api-base-url", help="Last9 API base url", required=False, default='')
    parser.add_argument("--org", help="Last9 API org", required=False, default='')
    parser.add_argument("--api-write-refresh-token", help="Last9 API write refresh token", required=False, default='')
    parser.add_argument(
        "--dry", action="store_true", dest="dry_run", help="Do dry run", default=os.environ.get('DRY_RUN', '1')
    )
    parser.add_argument("--no-dry", action="store_false", dest="dry_run", help="Do not do dry run")
    parser.set_defaults(dry_run=False)
    parser.add_argument("--overwrite", action="store_true", dest="overwrite", help="Overwrite existing dashboard")
    parser.add_argument(
        "--no-overwrite", action="store_false", dest="overwrite", help="Do not overwrite existing dashboard"
    )
    parser.set_defaults(overwrite=False)
    parser.add_argument("--log-level", help="Log level", default=os.environ.get("LOG_LEVEL", "INFO"))
    return vars(parser.parse_args(sys.argv[1:]))


# pylint: disable=too-many-branches
# pylint: disable=too-many-return-statements
def validate_args(args):
    """Validate input args"""
    # Validate input file exists
    if not os.path.exists(args['input_file']):
        logging.error("input_file - %s does not exist", args["input_file"])
        return False

    # Validate input file is valid json
    args['input_payload'] = {}
    try:
        with open(args['input_file'], 'r', encoding='utf-8') as input_fd:
            args['input_payload'] = json.load(input_fd)
    except Exception as ex:
        logging.error("input_file - %s failed to load json - caught exception - %s", args["input_file"], str(ex))
        return False

    # Validate if api_config_string is provided then other API args are not provided i.e.
    # api_base_url, org and api_write_refresh_token are not provided
    if args['api_config_str'] != '':
        got_error = False
        if args['api_base_url'] != '':
            logging.error(
                "Cannot provide api_config_str=%s and api_base_url=%s together",
                args['api_config_str'],
                args['api_base_url'],
            )
            got_error = True

        if args['org'] != '':
            logging.error("Cannot provide api_config_str=%s and org=%s together", args['api_config_str'], args['org'])
            got_error = True

        if args['api_write_refresh_token'] != '':
            logging.error(
                "Cannot provide api_config_str=%s and api_write_refresh_token=%s together",
                args['api_config_str'],
                args['api_write_refresh_token'],
            )
            got_error = True

        if got_error:
            return False

    # Validate that api_config_string is valid json and has the mandatory args to set the args variables i.e.
    # set api_base_url, org and api_write_refresh_token
    try:
        args['api_config_ds'] = json.loads(args['api_config_str'])
        args['api_write_refresh_token'] = (
            args['api_config_ds'].get('api_config', {}).get('write', {}).get('refresh_token', '')
        )
        args['api_base_url'] = args['api_config_ds'].get('api_config', {}).get('write', {}).get('api_base_url', '')
        args['org'] = args['api_config_ds'].get('api_config', {}).get('write', {}).get('org', '')
    except Exception as ex:
        logging.error("api_config_str=%s failed to load json - caught exception - %s", args["api_config_str"], str(ex))
        return False

    if len(args['api_write_refresh_token']) == 0:
        if len(args['api_config_str']) > 0:
            logging.error("api_config_str=%s failed to get api_config.write.refresh_token", args["api_config_str"])
        else:
            logging.error("api_write_refresh_token empty")
        return False

    if len(args['api_base_url']) == 0:
        if len(args['api_base_url']) > 0:
            logging.error("api_config_str=%s failed to get api_config.write.api_base_url", args["api_config_str"])
        else:
            logging.error("api_base_url empty")
        return False

    if len(args['org']) == 0:
        if len(args['org']) > 0:
            logging.error("api_config_str=%s failed to get api_config.write.org", args["api_config_str"])
        else:
            logging.error("org empty")
        return False

    return True


def get_write_token(args):
    """Get write token from read refresh token"""
    url = f"{args['api_base_url']}/oauth/access_token"
    headers = {
        "Content-Type": "application/json",
    }
    data = {"refresh_token": args['api_write_refresh_token']}

    response = requests.post(url, headers=headers, json=data, timeout=60)

    try:
        response.raise_for_status()
    except requests.exceptions.HTTPError as ex:
        err_msg = f"Failed to call {url} - caught_exception={str(ex)}"
        logging.error(err_msg)
        return False

    return response.json()['access_token']


def _extract_domain(url):
    parsed_url = urlparse(url)
    if parsed_url.netloc:
        return parsed_url.netloc
    return False


def create_dashboard(args):
    """Create Grafana dashboard"""
    domain = _extract_domain(args['api_base_url'])
    if domain is False:
        return False

    url = f"https://{domain}/api/gp/v1/organizations/{args['org']}/api/dashboards/db"
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-LAST9-API-TOKEN': f"Bearer {args['api_write_token']}",
    }

    if args['dry_run']:
        logging.info("dry_run set - skipping dashboard creation")
        return True

    if args['overwrite']:
        args['input_payload']['overwrite'] = True

    response = requests.post(url, headers=headers, data=json.dumps(args['input_payload']), timeout=60)
    try:
        response.raise_for_status()
    except requests.exceptions.HTTPError as ex:
        status_code = response.status_code
        response_ds = response.json()
        if str(status_code) == '412' and response_ds['status'] == 'name-exists' and not args['overwrite']:
            logging.warning("Got response=%s - ignoring as --no-overwrite flag set", str(response_ds))
            return True

        err_msg = f"Failed to call {url} - caught_exception={str(ex)} - response={response.json()}"
        logging.error(err_msg)
        return False

    logging.info("Dumping output")
    logging.info(response.json())
    return True


def setup_logging(log_level):
    """Setup logging"""
    log_level = getattr(logging, log_level.upper())
    logging.basicConfig(
        level=log_level, format="%(asctime)s.%(msecs)03d %(levelname)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
    )
    return True


def main():
    """Main function"""
    args = load_args()

    if not setup_logging(args["log_level"]):
        return 1

    if not validate_args(args):
        return 1

    args['api_write_token'] = get_write_token(args)
    if args['api_write_token'] is False:
        return 1

    logging.debug("Dumping args")
    logging.debug(json.dumps(args, indent=2))

    if not create_dashboard(args):
        return 1

    return 0


if __name__ == "__main__":
    exit_status = main()
    sys.exit(exit_status)
