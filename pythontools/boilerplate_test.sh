#!/usr/bin/env bash
# install lib_bash
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/check_and_install_lib_bash.sh"
source /usr/lib/local/lib_bash/lib_bash.sh
elevate "$@"
update_caller "$@"
log "OK"
