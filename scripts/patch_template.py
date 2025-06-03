#!/usr/bin/env python

"""
Sample usage

python scripts/patch_template.py --tmpl-file templates/alerts/vmagent/health.yaml --tmpl-vars-file templates/config/vmagent.toml
"""

import sys
import os
import argparse
import json
import logging
import traceback
from string import Template
import toml


def load_args():
    """Parse cli"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--tmpl-file", help="Template to patch", required=True)
    parser.add_argument("--tmpl-vars-file", help="Template vars file", required=True)
    parser.add_argument("--tmpl-vars-file-section", help="Template vars file section", required=True)
    parser.add_argument(
        "--ignore-missing-vars",
        action="store_true",
        dest="ignore_missing_vars",
        help="Ignore if template vars do not have values",
    )
    parser.add_argument(
        "--no-ignore-missing-vars",
        action="store_false",
        dest="ignore_missing_vars",
        help="Do not ignore if template vars do not have values",
    )
    parser.set_defaults(ignore_missing_vars=False)
    parser.add_argument("--log-level", help="Log level", default=os.environ.get("LOG_LEVEL", "INFO"))
    return vars(parser.parse_args(sys.argv[1:]))


def validate_args(args) -> bool:
    """Validate input args"""
    has_valid_args = True
    if not os.path.exists(args["tmpl_file"]):
        logging.error("Template file - %s does not exist", args["tmpl_file"])
        has_valid_args = False
    return has_valid_args


def patch_template(args):

    tmpl_file = args["tmpl_file"]
    tmpl_vars_file = args["tmpl_vars_file"]
    tmpl_vars_file_section = args["tmpl_vars_file_section"]
    ignore_missing_vars = args["ignore_missing_vars"]

    # Overwrite with any variables present in the input file
    tmpl_vars_file_ds = toml.load(tmpl_vars_file)
    if tmpl_vars_file_section not in tmpl_vars_file_ds:
        logging.error(
            "Failed to find tmpl_vars_file_section=%s in tmpl_vars_file=%s", tmpl_vars_file_section, tmpl_vars_file
        )
        return False

    # Load any environment variables following template var format
    for key, value in os.environ.items():
        if key.startswith("tmpl_var"):
            tmpl_vars_file_ds[tmpl_vars_file_section][key] = value

    logging.debug("Dumping template vars")
    logging.debug(json.dumps(tmpl_vars_file_ds, indent=2))

    input_fd = open(tmpl_file, encoding="utf-8")
    input_str = "".join(input_fd.readlines())
    tmpl_str = Template(input_str)

    try:
        if ignore_missing_vars:
            output_str = tmpl_str.safe_substitute(**tmpl_vars_file_ds[tmpl_vars_file_section])
        else:
            output_str = tmpl_str.substitute(**tmpl_vars_file_ds[tmpl_vars_file_section])
    except Exception:
        logging.error(
            "Failed to patch template file - %s - Caught exception - %s",
            tmpl_file,
            str(traceback.format_exc()),
        )
        return False

    return output_str


def setup_logging(log_level):
    log_level = getattr(logging, log_level.upper())
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s.%(msecs)03d %(levelname)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    return True


def main():
    """Patch template"""

    args = load_args()
    if not validate_args(args):
        return 1

    if not setup_logging(args["log_level"]):
        return 1

    # output_str = patch_template(args['tmpl_file'], args['tmpl_vars_file'], args['tmpl_vars_file_section'])
    output_str = patch_template(args)
    if output_str is False:
        return 1

    print(output_str)
    return 0


if __name__ == "__main__":
    exit_status = main()
    sys.exit(exit_status)
