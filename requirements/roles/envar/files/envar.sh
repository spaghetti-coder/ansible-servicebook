#!/usr/bin/env bash

_envar_complete() {
  local current="${COMP_WORDS[COMP_CWORD]}"
  # local previous=${COMP_WORDS[COMP_CWORD-1]}

  # shellcheck disable=SC2086
  if [ ${COMP_CWORD} -eq 1 ]; then
    # # TODO: fix issue with spaces in path
    # # https://stackoverflow.com/a/5608358 - BusyBox printf doesn't support '%q'
    # local files; files="$(
    #   local path="${current}"
    #   declare -a trim_filter=(sed -e 's/^\.\///')
    #   [[ "${path}" == './'* ]] && trim_filter=(cat)

    #   if [ -z "${path}" ] || [ -d "$(realpath -- "${path}" 2>/dev/null)" ]; then
    #     declare -a finder=(find -L -- "${path:-.}" -maxdepth 1 -mindepth 1)

    #     {
    #       "${finder[@]}" -type f -and '(' -name '*.sh' -o -name '*.env' ')' 2>/dev/null \
    #       | sort -n
    #       "${finder[@]}" -type d -exec printf -- '%s/\n' {} \; 2>/dev/null | sort -n
    #     } | "${trim_filter[@]}"
    #   elif ls -- "${path}"* &>/dev/null; then
    #     declare -a lister=(ls -1 -A -p)

    #     {
    #       # https://askubuntu.com/a/811236
    #       "${lister[@]}" -- "${path}"* 2>/dev/null | grep -v '\/$' | grep -e '\.sh$' -e '\.env$'
    #       "${lister[@]}" -d -- "${path}"* 2>/dev/null | grep '\/$'
    #     } | "${trim_filter[@]}"
    #   fi
    # )"

    # # shellcheck disable=SC2207
    # COMPREPLY=($(compgen -W "loaded desks req${files:+ }${files}" -- "${current}"))

    # shellcheck disable=SC2207
    COMPREPLY=($(compgen -W "loaded desks req" -- "${current}"))
  fi
}

# shellcheck disable=SC2317
_envar_lib() (
  local THE_LIB="${FUNCNAME[0]}"
  local THE_TOOL=envar
  local BIN_FILE="/opt/varlog/${THE_TOOL}/${THE_TOOL}.sh"

  [ "${FUNCNAME[1]}" = "${THE_TOOL}" ] || {
    echo "Direct '${THE_LIB}' usage is not allowed, use '${THE_TOOL}'" >&2
    return 1
  }

  local GLOBAL_DIR="/etc/${THE_TOOL}"
  local USER_DIR_SUFFIX=".${THE_TOOL}.d"
  local IGNORE_GLOBAL_FILE="${USER_DIR_SUFFIX}/_global.skip.sh"
  local IGNORE_PS1_SUFFIX_FILE="${USER_DIR_SUFFIX}/_ps1-suffix.skip.sh"
  local DEMO_FILE="${GLOBAL_DIR}/demo.skip.sh"
  local DEMO_DESK_FILE="${GLOBAL_DIR}/demo-desk.skip.sh"

  #
  # Tool functions
  #

  list_req()     { printf -- '%s' "${ENVAR_REQ}${ENVAR_REQ:+$'\n'}"; }
  list_loaded()  { printf -- '%s' "${ENVAR_LOADED}${ENVAR_LOADED:+$'\n'}"; }
  list_desks()   { printf -- '%s' "${ENVAR_DESKS}${ENVAR_DESKS:+$'\n'}"; }

  #
  # Setup functions
  #

  self_install() {
    [ "$(id -u)" -eq 0 ] || {
      echo "Installation requires root privileges" >&2
      return 1
    }

    local changed=false

    if true \
      && ${ENVAR_CONTEXT_SCRIPT:-false} \
      && ! [ "$(realpath -- "${0}" 2>/dev/null)" = "${BIN_FILE}" ] \
      && ! check_bin_source_integrity "${BIN_FILE}" \
    ; then
      # Not `envar install` or `${BIN_FILE} install`
      make_bin_file_code | (set -x; umask 0022; install -D -m 0755 -- <(cat) "${BIN_FILE}") || return
      changed=true
    fi

    if ! { true \
      && cmp -- <(print_demo) "${DEMO_FILE}" \
      && cmp -- <(print_demo_desk) "${DEMO_DESK_FILE}"
    } &>/dev/null ; then
      # shellcheck disable=SC2031
      (set -x; umask 0022; mkdir -p -- "${GLOBAL_DIR}") || return
      print_demo | (set -x; umask 0022; tee -- "${DEMO_FILE}" >/dev/null) || return
      print_demo_desk | (set -x; umask 0022; tee -- "${DEMO_DESK_FILE}" >/dev/null) || return

      changed=true
    fi

    if ${changed}; then echo "Done"; else echo "Unchanged"; fi
  }

  user_setup() {
    local user="${1:-$(id -u -n)}"
    local changed=false

    # shellcheck disable=SC2015
    {
      # User validation

      user="$(id -u -n -- "${user}")" || return
      local entry; entry="$(getent passwd | grep "^\s*${user}:")"

      local home; home="$(cut -d: -f 6 <<< "${entry}")" && {
        [ -d "$(realpath -- "${home}" 2>/dev/null)" ]
      } || {
        echo "Invalid user '${user}' home directory '${home}'" >&2
        return 1
      }

      local shell; shell="$(cut -d: -f 7 <<< "${entry}")" && {
        grep -qFx -- "${shell}" /etc/shells
      } || { echo "Invalid user '${user}' shell '${shell}'" >&2; return 1; }
    }

    if [ "$(id -u)" -eq 0 ]; then
      local result; result="$(self_install)" || return  # <- Ensure installation
      [ "${result,,}" = 'done' ] && changed=true
    elif ! [ -r "${BIN_FILE}" ]; then
      printf -- '%s\n' \
        "'${BIN_FILE}' installation is not accessible." \
        "Run with root privileges" \
      >&2; return 1
    elif true \
      && ! [ "$(realpath -- "${0}" 2>/dev/null)" = "${BIN_FILE}" ] \
      && ${ENVAR_CONTEXT_SCRIPT:-false} \
      && ! check_bin_source_integrity "${BIN_FILE}" \
    ; then
      # Running installation script as non-root with source different from ${BIN_FILE}.

      printf -- '%s\n' \
        "Install script code differs from '${BIN_FILE}'." \
        "Run with root privileges to upgrade" \
      >&2; return 1
    fi

    if [ "${user}" = "$(id -u -n)" ]; then
      if ! file_sources_tool ~/.bashrc; then
        {
          grep -q '[^\s]' ~/.bash_profile 2>/dev/null && echo
          printf -- '%s\n' ". '${BIN_FILE}' # { ENVARRED /}"
        } | (set -x; umask 0077; tee -a ~/.bashrc >/dev/null) || return

        changed=true
      fi

      if [ -r ~/.bash_profile ] || ! [ -r ~/.profile ]; then
        # ~/.bash_profile takes precedence over ~/.profile

        if ! file_sources_tool ~/.bash_profile; then
          {
            grep -q '[^\s]' ~/.bash_profile 2>/dev/null && echo
            echo 'if [ -f ~/.bashrc ]; then . ~/.bashrc; fi'
          } | (
            set -x; umask 0077; tee -a ~/.bash_profile >/dev/null
          ) || return

          changed=true
        fi
      elif ! file_sources_tool ~/.profile; then
        {
          grep -q '[^\s]' ~/.bash_profile 2>/dev/null && echo
          # shellcheck disable=SC2016
          printf -- '%s\n' \
            'if [ -n "$BASH_VERSION" ]; then' \
            '  if [ -f ~/.bashrc ]; then . ~/.bashrc; fi' \
            'fi'
        } | (
          set -x; umask 0077; tee -a ~/.profile >/dev/null
        ) || return

        changed=true
      fi

      if ! [ -d "$(realpath -- ~/"${USER_DIR_SUFFIX}" 2>/dev/null)" ]; then
        (set -x; install -d ~/"${USER_DIR_SUFFIX}") || return
        changed=true
      fi
    elif [[ $(id -u) -eq 0 ]]; then
      local result; result="$(
        su -l "${user}" -s /bin/bash -c "
          $(declare -f)
          ENVAR_CONTEXT_SCRIPT=${ENVAR_CONTEXT_SCRIPT:-false} ${THE_TOOL} setup
        "
      )" || return

      [ "${result,,}" = 'done' ] && changed=true
    else
      echo "Can't setup for '${user}' without root privileges" >&2
      return 1
    fi

    if ${changed}; then echo "Done"; else echo "Unchanged"; fi
  }

  #
  # Service functions
  #

  gen_init() {
    [ "${FUNCNAME[0]}" = gen_init ] && {
      declare -f "${FUNCNAME[0]}" | sed -e '/{/,$!d' -e '1s/.*{/{/' \
      | sed -e 's#{{\s*GLOBAL_DIR\s*}}#'"${GLOBAL_DIR}"'#g' \
            -e 's#{{\s*USER_DIR_SUFFIX\s*}}#'"${USER_DIR_SUFFIX}"'#g'
      return
    }

    if (return 0 2>/dev/null); then
      ENVAR_LOADED=""
      ENVAR_REQ=""

      eval "$(envar gen-env-loader '{{ GLOBAL_DIR }}')"
      eval "$(envar gen-env-loader ~/'{{ USER_DIR_SUFFIX }}')"
      eval "$(envar gen-desk-loader)"
      eval "$(declare -f _envar_complete)"
      # complete -o nosort -o nospace -o default -F _envar_complete envar 2>/dev/null
      complete -o nosort -o default -F _envar_complete envar 2>/dev/null
    else
      ENVAR_CONTEXT_SCRIPT=true envar "${@}"
    fi
  }

  gen_env_loader() {
    [ "${FUNCNAME[0]}" = gen_env_loader ] && {
      local env_dir="${1}"

      declare -f "${FUNCNAME[0]}" | sed -e '/{/,$!d' -e '1s/.*{/{/' `# <- Extract function body` \
      | sed -e 's#{{\s*GLOBAL_DIR\s*}}#'"${GLOBAL_DIR}"'#g' \
            -e 's#{{\s*ENV_DIR\s*}}#'"${env_dir}"'#g' \
            -e 's#{{\s*IGNORE_GLOBAL_FILE\s*}}#'"${IGNORE_GLOBAL_FILE}"'#g'
      return
    }

    declare envar_files_Ur6tbG; {
      # Load environments

      env_dir_Ur6tbG='{{ ENV_DIR }}'

      # shellcheck disable=SC2030
      envar_files_Ur6tbG="$(
        GLOBAL_DIR='{{ GLOBAL_DIR }}'
        IGNORE_GLOBAL_FILE='{{ IGNORE_GLOBAL_FILE }}'

        [ -r "${env_dir_Ur6tbG}" ] || exit
        [ -d "$(realpath -- "${env_dir_Ur6tbG}" 2>/dev/null)" ] || exit
        [ "${env_dir_Ur6tbG}" = "${GLOBAL_DIR}" ] && [ -e ~/"${IGNORE_GLOBAL_FILE}" ] && exit 1

        find -L -- "${env_dir_Ur6tbG}" -maxdepth 1 -type f `# -readable # <- Not supported by BusyBox find` \
          '(' -name '*.sh' -not -name '*.skip.sh' ')' \
          -o '(' -name '*.env' -not -name '*.skip.env' ')' \
          | sort -n | grep '.'
      )" && while read -r envar_file_Ur6tbG; do
        if ! [ -r "${envar_file_Ur6tbG}" ]; then
          [ -O "${env_dir_Ur6tbG}" ] && { # <- If owned by me, it's no good that can't read it
            ENVAR_REQ+="${ENVAR_REQ:+$'\n'}${envar_file_Ur6tbG}"
            echo "Warning: can't open '${envar_file_Ur6tbG}'" >&2
          }

          continue
        fi

        ENVAR_REQ+="${ENVAR_REQ:+$'\n'}${envar_file_Ur6tbG}"

        # shellcheck disable=SC1090
        . "${envar_file_Ur6tbG}"
        ENVAR_LOADED+="${ENVAR_LOADED:+$'\n'}${envar_file_Ur6tbG}"
      done <<< "${envar_files_Ur6tbG}"

      unset env_dir_Ur6tbG envar_files_Ur6tbG envar_file_Ur6tbG
    }

    true # <- No negative impact if last command exit code is non-0
  }

  gen_desk_loader() {
    [ "${FUNCNAME[0]}" = gen_desk_loader ] && {
      declare -f "${FUNCNAME[0]}" | sed -e '/{/,$!d' -e '1s/.*{/{/' `# <- Extract function body` \
      | sed -e 's#{{\s*IGNORE_PS1_SUFFIX_FILE\s*}}#'"${IGNORE_PS1_SUFFIX_FILE}"'#g'
      return
    }

    if [ -n "${ENVAR_DESK}" ]; then
      ENVAR_DESK="$(
        if cd -- "$(dirname -- "${ENVAR_DESK}")" &>/dev/null; then
          echo "$(pwd)/$(basename -- "${ENVAR_DESK}")" 2>/dev/null
        else
          printf -- '%s\n' "${ENVAR_DESK}"
        fi
      )"
      # shellcheck disable=SC2030
      ENVAR_DESKS+="${ENVAR_DESKS:+$'\n'}${ENVAR_DESK}"
    fi

    # Load desks
    [ -n "${ENVAR_DESKS}" ] && while read -r _envar_desk; do
      ENVAR_REQ+="${ENVAR_REQ:+$'\n'}${_envar_desk}"
      head -c 1 -- "${_envar_desk}" &>/dev/null || {
        if [ -n "${ENVAR_DESK}" ]; then
          echo "Error: failed to load '${_envar_desk}' desk" >&2
          exit 1
        fi

        echo "Warning: can't open '${_envar_desk}' desk file" >&2
        continue
      }

      # shellcheck disable=SC1090
      . "${_envar_desk}"
      ENVAR_LOADED+="${ENVAR_LOADED:+$'\n'}${_envar_desk}"

      _envar_last_desk="${_envar_desk}"
    done <<< "$(
      # https://unix.stackexchange.com/a/194790 modified for last wins
      tac <<< "${ENVAR_DESKS}" \
      | cat -n | sort -k2 -k1n | uniq -f1 | sort -nk1,1 | cut -f2- | tac
    )"

    unset ENVAR_DESK _envar_desk

    # Set PS1
    ENVAR_PS1_ORIGIN="${ENVAR_PS1_ORIGIN-${PS1}}"
    if [ -n "${_envar_last_desk}" ]; then
      PS1="$(
        # shellcheck disable=SC2030
        IGNORE_PS1_SUFFIX_FILE='{{ IGNORE_PS1_SUFFIX_FILE }}'

        if ! [ -e ~/"${IGNORE_PS1_SUFFIX_FILE}" ]; then
          # shellcheck disable=SC1090
          if (unset -f envar_ps1_suffix; . "${_envar_last_desk}" &>/dev/null; declare -F envar_ps1_suffix &>/dev/null); then
            declare candidate; candidate="$(envar_ps1_suffix | grep '.\+')" && {
              printf -- '%s' "${ENVAR_PS1_ORIGIN}"
              tail -n 1 <<< "${ENVAR_PS1_ORIGIN}" | grep -q '\s\+$' || printf -- ' '
              tail -n 1 <<< "${candidate}" | grep -q '\s\+$' || candidate+=' '
              printf -- '%s' "${candidate}"

              exit
            }
          else
            basename -- "${_envar_last_desk}" | rev | cut -d'.' -f2- | rev | {
              printf -- '%s' "${ENVAR_PS1_ORIGIN}"
              tail -n 1 <<< "${ENVAR_PS1_ORIGIN}" | grep -q '\s\+$' || printf -- ' '
              printf -- '%s > ' "$(cat)"
            }

            exit
          fi
        fi

        printf -- '%s' "${ENVAR_PS1_ORIGIN}"
      )"

      unset _envar_last_desk
    fi

    true # <- No negative impact if last command exit code is non-0
  }

  #
  # Info functions
  #

  print_help() {
    local installer; installer="/tmp/$(basename -- "${BIN_FILE}")"
    head -c 3 -- "$(realpath -- "${0}" 2>/dev/null)" 2>/dev/null | grep -q '^#!' \
      && installer="/tmp/$(basename -- "${0}")"

    # shellcheck disable=SC2001,SC2016,SC2031
    sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/^,//' <<< "
      This tool unclutters you .bashrc by autoloading environments from ${GLOBAL_DIR}
      and ~/${USER_DIR_SUFFIX} directories and using desks (desks are ividually loaded files).
     ,
      SETUP:
      =====
    "

    # shellcheck disable=SC2031
    if ${ENVAR_CONTEXT_SCRIPT} && ! [ "$(realpath -- "${0}" 2>/dev/null)" = "${BIN_FILE}" ]; then
      sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/^,//' <<< "
        # '${installer}' represents the current script somewhere in the file system, but
        # NOT in ${BIN_FILE}, which is the installation path.
       ,
        # (Only root) Install and create global configuration directory and demo files.
        ${installer} install
       ,
        # When ran by root, install, global configure and setup for USER (defaults to
        # current). For non-root (USER must be ometted or to be the current user) only
        # setup for the user
        ${installer} setup [USER]
       ,
        # Basically the most straight forward scenario:
        ${installer} install  # <- Only root user can do that
        ${installer} setup    # <- Run by each user who wants it
        . ~/.bashrc         # <- Reload the environment to accept tool
        ${THE_TOOL} -h      # <- View help for the tool
      "
    else
      sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/^,//' <<< "
        # ${BIN_FILE} and ${THE_TOOL} are interchangable in setup context.
        # ${THE_TOOL} becomes available to a user only after 'setup'
       ,
        # (Only root) Create global configuration directory and demo files. Can be
        # useful when you removed some and want to restore).
        ${THE_TOOL} install
       ,
        # If root, global configure and setup for USER (defaults to current).
        # If non-root, setup (only when USER is omitted or =\${USER})
        ${THE_TOOL} setup [USER]
       ,
        # For internal usage
        ${THE_TOOL} gen-init
        ${THE_TOOL} gen-env-loader ENV_DIR  # <- Allows joining more ENV_DIRs
        ${THE_TOOL} gen-desk-loader
      "
    fi

    if ! ${ENVAR_CONTEXT_SCRIPT}; then
      echo
      sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/^,//' <<< "
        USAGE:
        =====
        # For some more details on basic usage see ${DEMO_FILE}
       ,
        ${THE_TOOL} desk/path.sh  # <- Load desk, see ${DEMO_DESK_FILE}
        ${THE_TOOL} loaded        # <- View all loaded files
        ${THE_TOOL} desks         # <- View all loaded desk files
        ${THE_TOOL} req           # <- View all requested files
      "
    fi
  }

  print_demo() {
    # shellcheck disable=SC2001,SC2016,SC2031
    sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/^,//' <<< "
      #!/usr/bin/env bash
     ,
      # All *.sh and *.env files under ~/${USER_DIR_SUFFIX} loaded to the current shell but
      # *.skip.sh and *.skip.env files, they are ignored. Subdirectories are ignored.
      #
      # Same applies to ${GLOBAL_DIR} directory. To disable it:
      #   touch ~/${IGNORE_GLOBAL_FILE}
      #
      # This is a demo env that will not be loaded and serves as an example
      # as if it is loaded
     ,
      MY_VAR='demo value'   # <- Will be exported to the current shell
     ,
      my_func() { echo 'demo func'; } # <- Will be exported to the current shell
     ,
      # Unreadable files from ~/${USER_DIR_SUFFIX} provoke warnings. Files from ${GLOBAL_DIR} that
      # can't be read by the current user are silently skipped. This allows creating
      # global environments for specific groups. Usecase:
      echo \"echo 'gamers rock'\" | sudo tee /etc/envar/games-group.sh
      sudo chgrp games /etc/envar/games-group.sh
      sudo 0060 /etc/envar/games-group.sh
    "
  }

  print_demo_desk() {
    # shellcheck disable=SC2001,SC2016,SC2031
    sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/^,//' <<< '
      #!/usr/bin/env bash
     ,
      # Desk files are meant to be loaded individually with:
      #   '"${THE_TOOL} path/to/desk-file.sh"'  # <- Only *.sh and *.env supported
      # This will load a subshell with environment from the desk
      #
      # By default loaded desk appends desk file name (without extension) and
      # arrow to PS1: '\''DEFAULT_PS1 DESK_SUFFIX > '\''
      #
      # ```
      # # Usage demo:
      # touch ~/'"${IGNORE_PS1_SUFFIX_FILE}"'   # <- Disable PS1 suffixing
      # '"${THE_TOOL} ${DEMO_DESK_FILE}"'       # <- Load the current desk
      # ```
     ,
      MY_VAR="demo value"
     ,
      # envar_ps1_suffix() { echo "my-desk > "; }   # <- Custom PS1 suffix
      # envar_ps1_suffix() { return; }              # <- Dont'\'' PS1 suffix the desk
    '
  }

  #
  # Helper functions
  #

  declare -a GLOBAL_FUNCS=(
    _envar_complete
    "${THE_LIB}"
    "${THE_TOOL}"
  )

  # shellcheck disable=SC2016
  make_bin_file_code() {
    echo '#!/usr/bin/env bash'; echo
    declare -f -- "${GLOBAL_FUNCS[@]}"; echo
    echo 'eval "$(ENVAR_CONTEXT_SCRIPT=true '"${THE_TOOL}"' gen-init)"'
  }

  check_bin_source_integrity() {
    local file="${1}"

    # shellcheck disable=SC1090
    cmp -- <(make_bin_file_code) <(
      unset -f -- "${GLOBAL_FUNCS[@]}" &>/dev/null; . "${file}" &>/dev/null
      make_bin_file_code
    ) &>/dev/null
  }

  file_sources_tool() {
    local file="${1}"
    /usr/bin/env bash -i -c "
      unset -f -- ${GLOBAL_FUNCS[*]}
      . '${file}'; declare -F -- ${GLOBAL_FUNCS[*]}
    " &>/dev/null
  }

  "${@}"
)

envar() {
  local arg="${1}"; shift
  local the_lib=_envar_lib

  # Special marker allows running code depending on whether it's in envar.sh
  # script or 'envar' function context. Ensure unique var name
  local ENVAR_CONTEXT_SCRIPT="${ENVAR_CONTEXT_SCRIPT:-false}"

  declare -A PROXY_MAP=( # [COMMAND]=LIB_FUNCTION
    # Setup functions
    [install]=self_install
    [setup]=user_setup
    # Service functions
    [gen-init]=gen_init
    [gen-env-loader]=gen_env_loader
    [gen-desk-loader]=gen_desk_loader
  )

  ! ${ENVAR_CONTEXT_SCRIPT} && PROXY_MAP+=(
    # Tool functions can be accessed via ${THE_TOOL} only
    [loaded]=list_loaded
    [desks]=list_desks
    [req]=list_req
  )

  if [[ "${arg}" =~ ^(-\?|-h|--help)$ ]]; then
    "${the_lib}" print_help; return
  fi

  printf -- '%s\n' "${!PROXY_MAP[@]}" | grep -qFx -- "${arg}" && {
    "${the_lib}" "${PROXY_MAP[${arg}]}" "${@}"; return
  }

  if grep -q -- '\.\(sh\|env\)$' <<< "${arg}" && ! ${ENVAR_CONTEXT_SCRIPT}; then
    # shellcheck disable=SC2031
    ENVAR_DESKS="${ENVAR_DESKS}" ENVAR_DESK="${arg}" /usr/bin/env bash
    return
  fi

  echo "Envar: Invalid command '${arg}'" >&2
  return 1
}

eval "$(ENVAR_CONTEXT_SCRIPT=true envar gen-init)"
