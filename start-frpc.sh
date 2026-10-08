#!/bin/sh
# Start frpc in background when FRPC_ARG is non-empty; otherwise do nothing.
set -e

if [ -z "${FRPC_ARG:-}" ]; then
    echo "frpc: FRPC_ARG empty, skipping" >&2
    exit 0
fi

echo "frpc: starting with args: ${FRPC_ARG}" >&2
nohup /usr/local/bin/frpc ${FRPC_ARG} >/dev/null 2>&1 &
echo "frpc: started pid $!" >&2
