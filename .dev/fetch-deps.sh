#!/usr/bin/env bash

declare SELF_DIR; SELF_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# Keep all the logic in the lib for easy self-upgrade
# shellcheck disable=SC1091
. "${SELF_DIR}/fetch-deps.lib.sh"

(return 2>/dev/null) || fetch_deps "${@}"
