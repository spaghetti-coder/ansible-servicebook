#!/usr/bin/env bash

upgrade() {
  local SELF_DIR; SELF_DIR="$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
  declare -a THE_CMD=(play -t upgradable)

  main() {
    # shellcheck disable=SC1091
    . "${SELF_DIR}/play.sh"
    "${THE_CMD[@]}" "${@}"
  }

  main "${@}"
}

(return 2>/dev/null) || upgrade "${@}"
