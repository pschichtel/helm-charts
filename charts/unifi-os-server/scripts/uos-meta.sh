#!/bin/bash
# Firmware identity metadata, normally written to the shared /usr/lib by the
# UniFi OS firmware. Each component container has its own /usr/lib, so stamp
# the same console identity into it (idempotent) to make console detection
# (host-service / isUniFiOS) work outside of a real UOS install.
echo linux-x64 > /usr/lib/platform
echo "UniFi OS Server" > /usr/lib/product_name
echo UOSSERVER > /usr/lib/app_model
echo "UOSSERVER.0000000.5.1.42.000000.0000.0000" > /usr/lib/version
