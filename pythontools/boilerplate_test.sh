#!/usr/bin/env bash
# install lib_bash
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/check_and_install_lib_bash.sh"
source /usr/local/lib_bash/lib_bash.sh
elevate "$@"
update_caller "$@"
log "OK"
log_wrench "OK"
log_ok "OK"
log_success "OK"
