#!/bin/bash
set -euo pipefail
# Deliberately no internet-dependent package installation: dev has no NAT route.
printf 'Bluefin private development instance\n' > /etc/motd
install -d -m 0755 /opt/bluefin-dev
printf 'Baseline created at %s\n' "$(date -u +%FT%TZ)" > /opt/bluefin-dev/baseline.txt
