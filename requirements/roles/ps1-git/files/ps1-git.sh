#!/usr/bin/env bash

if [ -z "${BASH_VERSION}" ]; then
  # PS1-git is only available for bash

  (return 2>/dev/null) && return
  exit 0
fi

_iife_source_prompt() { unset _iife_source_prompt
  # git is not available, no need to try
  ! git --version &>/dev/null && return

  local f; for f in \
    /usr/share/git-core/contrib/completion/git-prompt.sh \
    /usr/lib/git-core/git-sh-prompt `# Debian` \
    /usr/share/git-core/git-prompt.sh \
  ; do
    declare -F __git_ps1 &>/dev/null && break

    # shellcheck disable=SC1090
    . "${f}" &>/dev/null
  done
}; _iife_source_prompt

# Preserved in order to be able to rollback to the original PS1
PS1_ORIGINAL="${PS1_ORIGINAL-${PS1}}"

# Preserved in order to be able to rollback to the PS1_GIT
# shellcheck disable=SC2034,SC2016
PS1_GIT="$(
  printf -- '%s%s%s\n' \
    '\[\033[01;31m\]\u@\h\[\033[00m\] \[\033[01;32m\]\w\[\033[00m\]' \
    '$(GIT_PS1_SHOWDIRTYSTATE=1 __git_ps1 '\'' (\[\033[01;33m\]%s\[\033[00m\])'\'' 2>/dev/null)' \
    ' \[\033[01;33m\]\$\[\033[00m\] '
)"

# shellcheck disable=SC2016
PS1="${PS1_GIT}"
