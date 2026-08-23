#!/usr/bin/env bash
# Decodes output from the Python baker with the app's own decoder.
#
# The baker (~/PycharmProjects/liftbuddy-charts) reimplements the pack format in
# Python. Nothing but this script stops the two drifting: a renamed key or a
# changed date format would leave the app silently showing an empty chart.
# Run it after any change to ChartPack or to the baker.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --package-path liftBuddyKit
swiftc -I liftBuddyKit/.build/debug/Modules -I liftBuddyKit/.build/debug \
       -L liftBuddyKit/.build/debug -lliftBuddyKit \
       Scripts/verify-chart-schema.swift -o /tmp/verify-chart-schema
/tmp/verify-chart-schema
