#!/usr/bin/env bash

fetch_deps() {
  local BASEBOOK_TGZ_URL='https://github.com/spaghetti-coder/ansible-basebook/archive/{{ BRANCH }}.tar.gz'
  local SELF_DIR; SELF_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
  local PROJ_DIR; PROJ_DIR="${SELF_DIR}/.."

  declare -A DEFAULTS=(
    [base_branch]=master
    [deps_file]=deps.ini
  )

  declare -A ARGS=(
    [is_help]=false
    [base_branch]="${DEFAULTS[base_branch]}"
    # [deps_file]="${DEFAULTS[deps_file]}"
  )

  parse_args() {
    while [ ${#} -gt 0 ]; do
      case "${1}" in
        -\?|-h|--help     ) ARGS[is_help]=true ;;
        -b|--base-branch  ) ARGS[base_branch]="${2}"; shift ;;
        *                 ) ARGS[deps_file]="${1}" ;;
      esac

      shift
    done
  }

  trap_help() {
    ${ARGS[is_help]} || return

    local self; self=fetch-deps.sh
    grep -q '.\+' -- "${0}" && self="$(basename -- "${0}")"

    _text_fmt "
      Pull dependencies from deps file and update helper scripts from basebook.
      By default reads deps.ini file from the project root directory

      Usage:
      =====
      ${self} [-b|--base-branch BRANCH=${DEFAULTS[base_branch]}] [DEPS_FILE=${DEFAULTS[deps_file]}]

      Demo:
      ====
      ${self} ./deps2.ini   # <- 'deps2.ini' file, '${DEFAULTS[base_branch]}' basebook git branch
      ${self} -b dev        # <- Use basebook 'dev' git branch
    "
  }

  init() {
    local branch_repl; branch_repl="$(sed -e 's/[\/&]/\\&/g' <<< "${ARGS[base_branch]}")"
    # shellcheck disable=SC2001
    BASEBOOK_TGZ_URL="$(sed -e 's/{{\s*BRANCH\s*}}/'"${branch_repl}"'/' <<< "${BASEBOOK_TGZ_URL}")"

    if [[ -n "${ARGS[deps_file]+x}" ]]; then
      cat -- "${ARGS[deps_file]}" >/dev/null || return
      ARGS[deps_file]="$(realpath --relative-to="${PROJ_DIR}" "${ARGS[deps_file]}")"
    else
      ARGS[deps_file]="${DEFAULTS[deps_file]}"
    fi
  }

  cp_books_files() {
    local reqs_dir=requirements

    local deps; ! deps="$(
      # Remove all blank and comment lines
      grep -v '^\s*\([#;].*\)\?\s*$' -- "${ARGS[deps_file]}" 2>/dev/null
    )" && return

    (set -x; rm -rf "${reqs_dir:?}"/{roles,*.*}; mkdir -p -- "${reqs_dir}") || return

    local line book_name dl_url temp_dir
    while IFS= read -r line; do
      book_name="${line%%=*}"
      dl_url="${line#*=}"

      temp_dir="$(set -x; mktemp -d)" || return
      ( set -o pipefail; set -x
        curl -fsSL -- "${dl_url}" \
        | tar --strip-components 1 -xzf - -C "${temp_dir}"
      ) || return

      if cat -- "${temp_dir}/playbook.yaml" &>/dev/null; then
        (set -x; cp -f -- "${temp_dir}/playbook.yaml" "${reqs_dir}/${book_name}.yaml") || return
      fi
      if cat -- "${temp_dir}/requirements.yaml" &>/dev/null; then
        (set -x; cp -f -- "${temp_dir}/requirements.yaml" "${reqs_dir}/${book_name}.req.yaml") || return
      fi
      if cat -- "${temp_dir}/deps.ini" &>/dev/null; then
        (set -x; cp -f -- "${temp_dir}/deps.ini" "${reqs_dir}/${book_name}.deps.ini") || return
      fi
      if [ -e "${temp_dir}/roles" ]; then
        (set -x; cp -rf -- "${temp_dir}/roles" "${reqs_dir}/") || return
      fi

      (set -x; rm -rf -- "${temp_dir:?}") || return 0
    done < <(
      sed -e 's/^\s*//' -e 's/\s*$//' -e 's/\s*=\s*/=/' <<< "${deps}"
    )
  }

  cp_base_scripts() {
    local tmp_base; tmp_base="$(mktemp -d)" || return
    ( set -x
      curl -fsSL -- "${BASEBOOK_TGZ_URL}" \
      | tar --strip-components 1 -xzf - -C "${tmp_base}" \
      && rm -- "${tmp_base}/.dev/fetch-deps.sh" \
      && cp -rf -- "${tmp_base}"/{.dev,bin} .
    ) || return

    (set -x; rm -rf -- "${tmp_base:?}") || return 0
  }

  _text_fmt() {
    local content; content="$(
      sed '/[^ ]/,$!d' <<< "${1-"$(cat)"}" | tac | sed '/[^ ]/,$!d' | tac
    )"
    local offset; offset="$(grep -o -m1 '^\s*' <<< "${content}")"
    sed -e 's/^\s\{0,'${#offset}'\}//' -e 's/\s\+$//' <<< "${content}"
  }

  main() {
    parse_args "${@}" || return
    trap_help && return
    init || return

    cd -- "${PROJ_DIR}" || return

    cp_base_scripts || return
    cp_books_files || return

    .dev/build-sample-vars.sh
  }

  main "${@}"
}

(return 2>/dev/null) || fetch_deps "${@}"
