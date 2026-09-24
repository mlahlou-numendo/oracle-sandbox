#!/bin/bash
# setup-symlinks.sh — Register all sandbox commands in /usr/local/bin.
# Creates symlinks so sandbox, sb, demasy, sqlcl, sqlplus, start-mcp,
# install-apex/start-apex/stop-apex/uninstall-apex, and
# download-oracle-components are available on PATH without full paths.

# Download helper
ln -s /usr/sandbox/app/system/download/download.sh /usr/local/bin/download-oracle-components

# CLI tools
ln -s /usr/sandbox/app/cli/sandbox.sh /usr/local/bin/demasy
ln -s /usr/sandbox/app/cli/sandbox.sh /usr/local/bin/sandbox
ln -s /usr/sandbox/app/cli/sandbox.sh /usr/local/bin/sb
ln -s /usr/sandbox/app/oracle/sqlplus/sqlplus-connect.sh /usr/local/bin/sqlplus
ln -s /usr/sandbox/app/oracle/sqlcl/sqlcl-connect.sh    /usr/local/bin/sqlcl

# MCP tools
ln -s /usr/sandbox/app/oracle/mcp/start.sh /usr/local/bin/start-mcp

# APEX tools
ln -s /usr/sandbox/app/oracle/apex/install.sh   /usr/local/bin/install-apex
ln -s /usr/sandbox/app/oracle/apex/start.sh     /usr/local/bin/start-apex
ln -s /usr/sandbox/app/oracle/apex/stop.sh      /usr/local/bin/stop-apex
ln -s /usr/sandbox/app/oracle/apex/uninstall.sh /usr/local/bin/uninstall-apex
