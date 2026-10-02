#!/usr/bin/env python3
#
# Copyright 2013 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Generates a shell or batch script to run a command."""

import argparse
import os
import string
import sys


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--output', required=True, help='Output file')
  parser.add_argument('--command', required=True, help='Command to run')
  parser.add_argument('--cwd', required=False, help='Working directory')
  parser.add_argument('rest', nargs='*', help='Arguments to pass to the command')

  # Rest of the arguments are passed to the command.
  args = parser.parse_args()

  out_path = os.path.dirname(args.output)
  if not os.path.exists(out_path):
    os.makedirs(out_path)

  script = string.Template(
      '''#!/bin/sh

set -e

# Set a trap to restore the working directory.
trap "popd > /dev/null" EXIT
pushd "$cwd" > /dev/null

$command $args
'''
  )

  params = {
      'command': args.command,
      'args': ' '.join(args.rest),
      'cwd': args.cwd if args.cwd else '',
  }

  with open(args.output, 'w') as f:
    f.write(script.substitute(params))

  # Make the script executable.
  os.chmod(args.output, 0o755)
  if args.output.endswith('gen_dartcli_call'):
    if os.path.exists('deflake_vpython_diag.txt'):
      with open('deflake_vpython_diag.txt') as df:
        print(df.read().strip())
    print('[DEFLAKE_DIAG] in_ninja sys_prefix=%s exe=%s' % (sys.prefix, sys.executable))
    cur = sys.prefix
    for _ in range(4):
      cur = os.path.dirname(cur)
      if os.path.isdir(cur):
        entries = os.listdir(cur)
        matches = [e for e in entries if 'eeaaiqs' in e or 'wheels' in e or 'venv' in e]
        if matches:
          print('[DEFLAKE_DIAG] in_ninja dir=%s matches=%s' % (cur, matches))


if __name__ == '__main__':
  main()
