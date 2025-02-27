#!/usr/bin/env bash

build_sample_vars() (
  local PROJ_DIR; PROJ_DIR="$(dirname -- "${BASH_SOURCE[0]}")/.."
  local DEST_FILE=sample/group_vars/all.yaml
  declare -a ROLES_PATHS=(. ./requirements)

  declare -A ARGS=(
    [is_help]=false
  )

  parse_args() {
    while [ ${#} -gt 0 ]; do
      case "${1}" in
        -\?|-h|--help     ) ARGS[is_help]=true ;;
      esac

      shift
    done
  }

  trap_help() {
    ${ARGS[is_help]} || return

    local self; self=build-sample-vars.sh
    grep -q '.\+' -- "${0}" && self="$(basename -- "${0}")"

    _text_fmt "
      Build sample vars file based on defaults in available roles.

      Usage:
      =====
      ${self}
    "
  }

  _get_default_files() {
    local append result
    local dir; for dir in "${@}"; do
      append="$(
        find "${dir}" -maxdepth 4 -type f \
          -path "${dir}/roles/*/defaults/main.yaml" \
        | sort -n | grep '.\+'
      )" || continue

      result+="${result:+$'\n'}${append}"
    done

    [[ -z "${result}" ]] || printf -- '%s\n' "${result}"
  }

  _get_vars() {
    local append result
    local role_name
    local file; for file in "${@}"; do
      append="$(
        sed -e '/^[^- ]/,$!d' -- "${file}" \
        | sed -e '/^\s*#\s*{{\s*NOAPP\s*}}\s*$/,$d'
      )"

      # Drop the file if there is no non-empty lines there
      ! grep -vq '^\s*$' <<< "${append}" && continue

      role_name="$(rev <<< "${file}" | cut -d'/' -f3 | rev)"

      # Skip demo-app role
      [ "${role_name}" == 'demo-app' ] && continue

      result+="${result:+$'\n\n'}"
      result+=$'###\n### '"${role_name^^}"
      result+=$'\n###\n'

      result+="${append}"
    done

    [[ -z "${result}" ]] || printf -- '%s\n' "${result}"
  }

  _patch_dest_file() {
    local vars_text="${1}"
    vars_text="${vars_text:+$'\n'${vars_text}$'\n'}"

    ( set -o pipefail
      sed '1,/^\s*#\+\s*{{\s*ROLES_CONF_TS4LE64m91\s*}}\s*\(#.*\)\?$/!d' -- "${DEST_FILE}" \
      | { cat; printf -- '%s' "${vars_text}"; } \
      | { set -x; tee -- "${DEST_FILE}" >/dev/null; }
    )
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

    cd -- "${PROJ_DIR}" || return

    declare -a default_files tmp_list
    local tmp; tmp="$(_get_default_files "${ROLES_PATHS[@]}")"

    [ -n "${tmp}" ] && mapfile -t tmp_list <<< "${tmp}"
    default_files+=("${tmp_list[@]}")

    local vars_text
    vars_text="$(_get_vars "${default_files[@]}")"

    _patch_dest_file "${vars_text}" || return
  }

  main "${@}"
)

(return 2>/dev/null) || build_sample_vars "${@}"
