#!/usr/bin/env python3
"""
Fetch existing alert definitions from Last9 API and save them as YAML files
"""

import os
import sys
import json
import argparse
import logging
import requests
from pathlib import Path
from typing import Dict, List, Optional, Any
from urllib.parse import urlparse

# Try to import yaml, install if needed
try:
    import yaml
except ImportError:
    print("PyYAML not found. Installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "PyYAML"])
    import yaml


def load_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description="Fetch alert definitions from Last9 API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Using config file:
  python3 scripts/fetch-alerts.py --config-file .last9.config.json

  # Using environment variables:
  export LAST9_API_CONFIG_STR='{"api_config": {...}}'
  python3 scripts/fetch-alerts.py

  # Specifying custom output directory:
  python3 scripts/fetch-alerts.py --output-dir my-alerts/

  # With API parameters directly:
  python3 scripts/fetch-alerts.py --api-base-url https://app.last9.io/api/v4 \\
      --org myorg --read-refresh-token xxx
        """
    )

    # Config sources (mutually exclusive)
    parser.add_argument(
        "--config-file",
        help="Path to .last9.config.json file",
        default=".last9.config.json"
    )
    parser.add_argument(
        "--api-config-str",
        help="Last9 API config JSON string (from LAST9_API_CONFIG_STR env var)",
        default=os.environ.get('LAST9_API_CONFIG_STR', '')
    )

    # Direct API parameters (alternative to config)
    parser.add_argument(
        "--api-base-url",
        help="Last9 API base URL",
        default=""
    )
    parser.add_argument(
        "--org",
        help="Last9 organization slug",
        default=""
    )
    parser.add_argument(
        "--read-refresh-token",
        help="Last9 API read refresh token",
        default=""
    )

    # Output configuration
    parser.add_argument(
        "--output-dir",
        help="Output directory for fetched alerts (default: ../<org>-alerts/)",
        default=""
    )

    # Filtering options
    parser.add_argument(
        "--filter-tags",
        help="Comma-separated list of tags to filter alerts",
        default=""
    )
    parser.add_argument(
        "--entity-class",
        help="Filter by entity class (default: alert-manager)",
        default="alert-manager"
    )

    # Behavior options
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be fetched without writing files"
    )
    parser.add_argument(
        "--log-level",
        help="Log level (DEBUG, INFO, WARNING, ERROR)",
        default=os.environ.get("LOG_LEVEL", "INFO")
    )

    return vars(parser.parse_args())


def validate_args(args: Dict) -> bool:
    """Validate and normalize arguments"""

    # Try to load config from file first
    if os.path.exists(args['config_file']):
        try:
            with open(args['config_file'], 'r') as f:
                config = json.load(f)

            # Extract API config
            iac_config = config.get('iac_config', {})
            api_config = iac_config.get('api_config', {})
            read_config = api_config.get('read', {})

            args['read_refresh_token'] = read_config.get('refresh_token', '')
            args['api_base_url'] = read_config.get('api_base_url', '')
            args['org'] = read_config.get('org', '')

            logging.info(f"Loaded configuration from {args['config_file']}")

        except Exception as ex:
            logging.error(f"Failed to load config file: {ex}")
            return False

    # Try environment variable if config file didn't work
    elif args['api_config_str']:
        try:
            config_ds = json.loads(args['api_config_str'])
            read_config = config_ds.get('api_config', {}).get('read', {})

            args['read_refresh_token'] = read_config.get('refresh_token', '')
            args['api_base_url'] = read_config.get('api_base_url', '')
            args['org'] = read_config.get('org', '')

            logging.info("Loaded configuration from LAST9_API_CONFIG_STR")

        except Exception as ex:
            logging.error(f"Failed to parse LAST9_API_CONFIG_STR: {ex}")
            return False

    # Validate required fields
    if not args['read_refresh_token']:
        logging.error("Read refresh token not provided")
        logging.error("Provide via --config-file, --api-config-str, or --read-refresh-token")
        return False

    if not args['api_base_url']:
        logging.error("API base URL not provided")
        return False

    if not args['org']:
        logging.error("Organization not provided")
        return False

    # Set default output directory based on org if not specified
    if not args['output_dir']:
        args['output_dir'] = f"../{args['org']}-alerts"
        logging.info(f"Using default output directory: {args['output_dir']}")

    # Ensure output directory exists (unless dry run)
    if not args['dry_run']:
        output_path = Path(args['output_dir'])
        output_path.mkdir(parents=True, exist_ok=True)
        logging.info(f"Output directory: {output_path.absolute()}")

    return True


def get_access_token(args: Dict) -> Optional[str]:
    """Exchange refresh token for access token"""
    url = f"{args['api_base_url']}/oauth/access_token"
    headers = {"Content-Type": "application/json"}
    data = {"refresh_token": args['read_refresh_token']}

    try:
        response = requests.post(url, headers=headers, json=data, timeout=60)
        response.raise_for_status()

        access_token = response.json()['access_token']
        logging.info("Successfully obtained access token")
        return access_token

    except requests.exceptions.RequestException as ex:
        logging.error(f"Failed to get access token: {ex}")
        if hasattr(ex, 'response') and ex.response is not None:
            logging.error(f"Response: {ex.response.text}")
        return None


def fetch_alerts(args: Dict, access_token: str) -> Optional[List[Dict]]:
    """Fetch all alert definitions from Last9 API"""

    # Possible API endpoint patterns to try
    # The exact endpoint may vary, so we try multiple patterns
    possible_endpoints = [
        f"{args['api_base_url']}/organizations/{args['org']}/entities",
        f"{args['api_base_url']}/entities",
        f"{args['api_base_url']}/alert-managers",
    ]

    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': f"Bearer {access_token}",
    }

    # Query parameters for filtering
    params = {
        'entity_class': args['entity_class']
    }

    alerts = []

    for url in possible_endpoints:
        try:
            logging.debug(f"Trying endpoint: {url}")
            response = requests.get(url, headers=headers, params=params, timeout=60)

            if response.status_code == 200:
                data = response.json()
                logging.info(f"Successfully fetched data from endpoint")

                # Extract alerts from response
                # Response structure may vary - handle different formats
                if isinstance(data, list):
                    alerts = data
                elif isinstance(data, dict):
                    # Try common keys
                    alerts = data.get('entities', data.get('data', data.get('results', [])))

                if alerts:
                    logging.info(f"Found {len(alerts)} alert definitions")
                    return alerts
                else:
                    logging.debug(f"No alerts found at this endpoint")

            elif response.status_code == 404:
                logging.debug(f"Endpoint not found: {url}")
            elif response.status_code == 401:
                logging.error("Authentication failed - check your tokens")
                return None
            elif response.status_code == 403:
                logging.error("Insufficient permissions - check token scope")
                return None
            else:
                logging.debug(f"Endpoint returned status {response.status_code}")

        except requests.exceptions.RequestException as ex:
            logging.debug(f"Endpoint {url} failed: {ex}")
            continue

    # If we get here, none of the endpoints worked
    logging.error("Could not fetch alerts from any known endpoint")
    logging.error("The Last9 API structure may have changed")
    logging.error("Please check the API documentation or contact Last9 support")
    logging.error("")
    logging.error("Attempted endpoints:")
    for url in possible_endpoints:
        logging.error(f"  - {url}")

    return None


def convert_to_yaml(alert_entity: Dict) -> Dict:
    """Convert API response format to IaC YAML format"""

    # The API response should already be in the correct format
    # but we'll normalize it to ensure consistency with template structure
    yaml_entity = {
        'name': alert_entity.get('name', ''),
        'entity_class': alert_entity.get('entity_class', 'alert-manager'),
        'type': alert_entity.get('type', ''),
        'external_ref': alert_entity.get('external_ref', ''),
    }

    # Add optional fields if present
    if 'data_source' in alert_entity:
        yaml_entity['data_source'] = alert_entity['data_source']

    if 'description' in alert_entity:
        yaml_entity['description'] = alert_entity['description']

    if 'tags' in alert_entity and alert_entity['tags']:
        yaml_entity['tags'] = alert_entity['tags']

    if 'ui_readonly' in alert_entity:
        yaml_entity['ui_readonly'] = alert_entity['ui_readonly']

    if 'indicators' in alert_entity and alert_entity['indicators']:
        yaml_entity['indicators'] = alert_entity['indicators']

    if 'alert_rules' in alert_entity and alert_entity['alert_rules']:
        yaml_entity['alert_rules'] = alert_entity['alert_rules']

    if 'notification_channels' in alert_entity and alert_entity['notification_channels']:
        yaml_entity['notification_channels'] = alert_entity['notification_channels']

    return yaml_entity


def save_alerts(args: Dict, alerts: List[Dict]) -> int:
    """Save alerts as YAML files to output directory"""

    if args['dry_run']:
        print("\n" + "="*60)
        print("DRY RUN - Would save the following alerts:")
        print("="*60)
        for alert in alerts:
            alert_name = alert.get('name', 'unnamed')
            print(f"  {alert_name}.yaml")
        return len(alerts), {}

    output_dir = Path(args['output_dir'])
    saved_count = 0
    type_counts = {}

    # Save each alert as a separate file directly in output directory
    for alert in alerts:
        alert_name = alert.get('name', 'unnamed').lower().replace(' ', '-').replace('_', '-')
        entity_type = alert.get('type', 'unknown').lower().replace(' ', '-')

        # Track counts by type for summary
        type_counts[entity_type] = type_counts.get(entity_type, 0) + 1

        # Convert to YAML format
        yaml_entity = convert_to_yaml(alert)

        # Wrap in entities array to match template format
        yaml_data = {
            'entities': [yaml_entity]
        }

        # Write YAML file directly in output directory
        output_file = output_dir / f"{alert_name}.yaml"

        try:
            with open(output_file, 'w') as f:
                yaml.dump(yaml_data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

            logging.info(f"Saved: {output_file}")
            saved_count += 1

        except Exception as ex:
            logging.error(f"Failed to save {output_file}: {ex}")

    return saved_count, type_counts


def print_summary(args: Dict, saved_count: int, type_counts: Dict[str, int]):
    """Print summary and next steps"""

    print("\n" + "="*60)
    print("              ALERT FETCH SUMMARY")
    print("="*60)

    if args['dry_run']:
        print(f"\nDRY RUN: Would fetch {saved_count} alerts")
    else:
        print(f"\n✓ Successfully fetched {saved_count} alerts")
        print(f"✓ Saved to: {Path(args['output_dir']).absolute()}")

        if type_counts:
            print("\nAlert breakdown by type:")
            for alert_type, count in sorted(type_counts.items()):
                print(f"  - {alert_type}: {count} alerts")

    print("\n" + "-"*60)
    print("              NEXT STEPS")
    print("-"*60)
    print("\n⚠ IMPORTANT: Review and test before deploying!")

    alerts_dir = Path(args['output_dir']).name

    print("\n1. Review the fetched alerts:")
    print(f"   $ cd {args['output_dir']}")
    print(f"   $ ls *.yaml")
    print(f"   $ cat <alert-name>.yaml")

    print("\n2. Edit alerts as needed (update thresholds, channels, etc.):")
    print(f"   $ vi <alert-name>.yaml")

    print("\n3. Test locally with l9iac plan from iac-template directory:")
    print(f"   $ cd ../iac-template")
    print(f"   $ source env/bin/activate")
    print(f"   $ ./scripts/run-iac.sh --run-all-files --plan")

    print("\n4. Review plan output carefully before proceeding")

    print(f"\n5. When satisfied, commit and push from {alerts_dir}/ directory:")
    print(f"   $ cd ../{alerts_dir}")
    print(f"   $ git add *.yaml")
    print(f"   $ git commit -m \"Add/update alerts\"")
    print(f"   $ git push")

    print("\n6. Monitor GitHub Actions to verify deployment")

    print("\n7. Check Last9 UI to confirm alerts are active")

    print("\n" + "="*60)
    print("\n💡 Tips:")
    print("  - Start with 1-2 alerts to test the workflow")
    print("  - Review notification channels before deploying")
    print("  - Adjust thresholds based on your environment")
    print(f"  - All YAML files in {alerts_dir}/ will be deployed")
    print()


def main() -> int:
    """Main execution flow"""
    args = load_args()

    # Setup logging
    log_level = getattr(logging, args['log_level'].upper())
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    # Validate configuration
    if not validate_args(args):
        logging.error("Configuration validation failed")
        logging.error("")
        logging.error("Make sure you have either:")
        logging.error("  1. A .last9.config.json file with Last9 API configuration")
        logging.error("  2. LAST9_API_CONFIG_STR environment variable set")
        logging.error("  3. CLI arguments: --api-base-url, --org, --read-refresh-token")
        return 1

    # Get access token
    logging.info("Authenticating with Last9 API...")
    access_token = get_access_token(args)
    if not access_token:
        logging.error("Authentication failed")
        return 1

    # Fetch alerts from API
    logging.info("Fetching alerts from Last9 API...")
    alerts = fetch_alerts(args, access_token)
    if alerts is None:
        return 1

    if not alerts:
        logging.warning("No alerts found")
        logging.info("This could mean:")
        logging.info("  - No alerts are configured in your Last9 tenant")
        logging.info("  - The entity_class filter doesn't match any alerts")
        logging.info("  - You don't have permission to read alerts")
        return 0

    # Save alerts to files
    saved_count, type_counts = save_alerts(args, alerts)

    # Print summary
    print_summary(args, saved_count, type_counts)

    return 0


if __name__ == "__main__":
    sys.exit(main())
