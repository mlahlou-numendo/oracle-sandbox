#!/bin/bash
# setup.sh — Image build-time setup orchestrator.
# Called once during docker build (RUN setup.sh) to configure the runtime image.
# Runs all admin scripts in dependency order: sql wrapper → symlinks → user → shell profile.

source /usr/sandbox/app/system/utils/paths.sh

$ADMIN/setup-sql-wrapper.sh
$ADMIN/setup-symlinks.sh
$ADMIN/setup-sandbox-user.sh
$CLI/setup-shell-profile.sh
