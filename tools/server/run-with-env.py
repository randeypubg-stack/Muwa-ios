#!/usr/bin/env python3
"""Load private server configuration without echoing it or putting it in argv."""
import os, pathlib, sys
for value in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if value and not value.startswith('#'):
        key, content = value.split('=',1)
        os.environ[key] = content
os.execvp(sys.argv[2],sys.argv[2:])
