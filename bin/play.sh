#!/usr/bin/env bash

# shellcheck disable=SC2317
play() (
  local PROJ_DIR; PROJ_DIR="$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")/.."
  local REQS_DIR=requirements
  local REQS_FILE=./requirements.yaml
  declare -a COLLECTIONS_CMD=(
    ansible-galaxy collection install -r "${REQS_FILE}" -p "${REQS_DIR}"
  )
  declare -a PLAYBOOK_CMD=(
    ansible-playbook ./playbook.yaml -i ./hosts.yaml
  )

  init() {
    if grep -qxf <(printf -- '%s\n' \
      '--list-.\+' \
      '-\(h\|-help\)' \
    ) <<< "${1}"; then
      COLLECTIONS_CMD=(true)
      return
    fi

    cat -- "${PROJ_DIR}/${REQS_FILE}" &>/dev/null || COLLECTIONS_CMD=(true)
    cat -- "${PROJ_DIR}/vaulted.txt" &>/dev/null && PLAYBOOK_CMD+=(-J)
  }

  main() {
    init "${@}"

    cd -- "${PROJ_DIR}" || return

    ( set -x
      "${COLLECTIONS_CMD[@]}" \
      && "${PLAYBOOK_CMD[@]}" "${@}"
    ) || return
  }

  main "${@}"
)

(return 2>/dev/null) || play "${@}"
