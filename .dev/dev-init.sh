#!/usr/bin/env bash

dev_init() (
  local SCRIPT_DIR; SCRIPT_DIR="$(dirname -- "$(realpath --relative-to="$(pwd)" -- "${0}")")"
  local PROJ_DIR; PROJ_DIR="$(dirname -- "${SCRIPT_DIR}")"

  hooks_install() {
    local hooks_path='.dev/git-hooks'

    cd "${PROJ_DIR}" || return
    (set -x; git config --local core.hooksPath "${hooks_path}") || return
  }

  main() {
    hooks_install || return
  }

  main "${@}"
)

(return 2>/dev/null) || dev_init "${@}"
