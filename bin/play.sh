#!/usr/bin/env bash

# shellcheck disable=SC2317
play() (
  local PROJ_DIR; PROJ_DIR="$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")/.."
  local REQS_DIR=requirements
  local REQS_FILE=./requirements.yaml
  declare -a COLLECTIONS_CMD=(
    ansible-galaxy collection install -r "${REQS_FILE}" -p "${REQS_DIR}"
  )

  init() {
    cat -- "${PROJ_DIR}/${REQS_FILE}" &>/dev/null || COLLECTIONS_CMD=(true)
  }

  main() {
    init

    cd -- "${PROJ_DIR}" || return

    ( set -x
      "${COLLECTIONS_CMD[@]}" \
      && ansible-playbook ./playbook.yaml -i ./hosts.yaml "${@}"
    ) || return
  }

  main "${@}"
)

(return 2>/dev/null) || play "${@}"
