#!/bin/bash
#
# Manage binaries.

# ------------------------------------ BEGIN GLOBAL VARIABLES ------------------------------------ #

# Absolute path to the physical script directory.
declare __DIR

# Script name.
declare __NAME

# JSON file containing all information about the supported binaries,
# i.e. name, download URL and so on.
declare BIN_DATA_FILE

# Parent directory for binaries. The path from here on to the binary itself
# should be: $BIN_PARENT_DIR/<binary name>/v<binary version>/<binary name>
declare BIN_PARENT_DIR

# Symbolic link directory for binaries. Must be within $PATH and accessible
# for the executing user.
declare BIN_LINK_DIR

# Convenience string for listing binary names and SemVer notice.
# Used in 'show_usage_of_*' functions.
declare ARGS_SECTION

# ############################################################################ #
# Convenience function to initialize global variables. This allows for more
# complex value assignments, i.e. function outputs or multi-line operations.
#
# Globals:
#   All.
# Arguments:
#   None.
# Outputs:
#   None.
# ############################################################################ #
init() {
  __DIR="$(cd "$(dirname "$(readlink -f "${0}")")" && pwd)"
  __NAME="$(basename "${0}")"

  BIN_DATA_FILE="${__DIR}/data.json"
  if [[ ! -e "${BIN_DATA_FILE}" ]]; then
    echo "${__NAME}: BIN_DATA_FILE '${BIN_DATA_FILE}' does not exist. Aborting."
    exit 1
  elif [[ ! -r "${BIN_DATA_FILE}" ]]; then
    echo "${__NAME}: read permission is not granted for BIN_DATA_FILE '${BIN_DATA_FILE}'. Aborting."
    exit 1
  fi

  BIN_PARENT_DIR="$(jq -r '.BIN_PARENT_DIR' "${BIN_DATA_FILE}")"
  if [[ "${BIN_PARENT_DIR}" == "null" ]]; then
    echo "${__NAME}: 'BIN_PARENT_DIR' must not be 'null'. Aborting."
    exit 1
  fi

  BIN_LINK_DIR="$(jq -r '.BIN_LINK_DIR' "${BIN_DATA_FILE}")"
  if [[ "${BIN_LINK_DIR}" == "null" ]]; then
    echo "${__NAME}: 'BIN_LINK_DIR' must not be 'null'. Aborting."
    exit 1
  fi

  ARGS_SECTION="\
Binaries:
$(
  while IFS='' read -r BIN_NAME; do
    echo "  ${BIN_NAME}"
  done < <(get_bin_names)
)

The version must be SemVer compliant (X.Y.Z), for example:
  1.0.0     compliant.
  v1.0.0    not compliant.
See 'https://semver.org/' for more information."
}

# ------------------------------------- END GLOBAL VARIABLES ------------------------------------- #

# ################################################################################################ #

# ------------------------------------- BEGIN PACKAGE - DEBUG ------------------------------------ #

# ############################################################################ #
# Do not print commands and their arguments as they are executed.
#
# Globals:
#   None.
# Arguments:
#   None.
# Outputs:
#   None.
# ############################################################################ #
debug::off() {
  set +x
}

# ############################################################################ #
# Print commands and their arguments as they are executed.
#
# Globals:
#   None.
# Arguments:
#   None.
# Outputs:
#   None.
# ############################################################################ #
debug::on() {
  set -x
}

# -------------------------------------- END PACKAGE - DEBUG ------------------------------------- #

# ################################################################################################ #

# -------------------------------------- BEGIN PACKAGE - ERR ------------------------------------- #

# ############################################################################ #
# Do not exit on error. The return value of a pipeline is the status of the
# last command.
#
# Globals:
#   None.
# Arguments:
#   None.
# Outputs:
#   None.
# ############################################################################ #
err::off() {
  set +eo pipefail
}

# ############################################################################ #
# Exit on error. The return value of a pipeline is the status of the last
# command to exit with a non-zero status, or zero if no command exited with
# a non-zero status.
#
# Globals:
#   None.
# Arguments:
#   None.
# Outputs:
#   None.
# ############################################################################ #
err::on() {
  set -eo pipefail
}

# --------------------------------------- END PACKAGE - ERR -------------------------------------- #

# ################################################################################################ #

# ---------------------------------------- BEGIN FUNCTIONS --------------------------------------- #

# ############################################################################ #
# Checks if a binary exists locally.
#
# Globals:
#   None.
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   0 if the binary exists locally, non-zero otherwise.
# ############################################################################ #
bin_exists_locally() {
  local BIN_NAME
  local BIN_VERSION
  local BIN_PATH

  BIN_NAME="${1}"
  BIN_VERSION="${2}"
  BIN_PATH="${BIN_PARENT_DIR}/${BIN_NAME}/v${BIN_VERSION}/${BIN_NAME}"

  [[ -e "${BIN_PATH}" ]]
}

# ############################################################################ #
# Checks if a binary is linked.
#
# Globals:
#   None.
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   0 if the binary is linked, non-zero otherwise.
# ############################################################################ #
bin_is_linked() {
  local BIN_NAME
  local BIN_VERSION
  local BIN_TARGET
  local BIN_LINK

  BIN_NAME="${1}"
  BIN_VERSION="${2}"
  BIN_TARGET="${BIN_PARENT_DIR}/${BIN_NAME}/v${BIN_VERSION}/${BIN_NAME}"
  BIN_LINK="${BIN_LINK_DIR}/${BIN_NAME}"

  [[ "${BIN_TARGET}" == "$(readlink "${BIN_LINK}")" ]]
}

# ############################################################################ #
# Checks if a binary name is valid.
# A binary name is valid if the following criteria are met:
# - the binary name is part of the output produced by 'get_bin_names'.
#
# Globals:
#   None.
# Arguments:
#   1 - binary name.
# Outputs:
#   0 if the binary name is valid, non-zero otherwise.
# ############################################################################ #
bin_name_is_valid() {
  local BIN_NAME
  local CUR_BIN_NAME

  BIN_NAME="${1}"

  while IFS='' read -r CUR_BIN_NAME; do
    if [[ "${BIN_NAME}" == "${CUR_BIN_NAME}" ]]; then
      return 0
    fi
  done < <(get_bin_names)

  return 1
}

# ############################################################################ #
# Checks if a binary version is valid.
# A binary version is valid if the following criteria are met:
# - the binary version matches the pattern '[0-9]+\.[0-9]+\.[0-9]+'.
#
# Globals:
#   None.
# Arguments:
#   1 - binary version.
# Outputs:
#   None.
# Returns:
#   0 if the binary version is valid, non-zero otherwise.
# ############################################################################ #
bin_version_is_valid() {
  local BIN_VERSION

  BIN_VERSION="${1}"

  [[ "${BIN_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ############################################################################ #
# Reads binary names (keys) from $BIN_DATA_FILE.
#
# Globals:
#   BIN_DATA_FILE.
# Arguments:
#   None.
# Outputs:
#   Writes binary names to stdout.
# ############################################################################ #
get_bin_names() {
  jq -r ".binaries[].name" "${BIN_DATA_FILE}"
}

# ############################################################################ #
# Reads commands from $BIN_DATA_FILE. The commands (array) are joined by '; '.
#
# Globals:
#   BIN_DATA_FILE.
# Arguments:
#   1 - binary name.
#   2 - level 1 key, i.e. 'download'.
#   3 - level 2 key, i.e. 'binary' or 'checksum'.
# Outputs:
#   Writes the joined commands to stdout.
# ############################################################################ #
get_exec() {
  local BIN_NAME
  local LEVEL_1_KEY
  local LEVEL_2_KEY
  
  BIN_NAME="${1}"
  LEVEL_1_KEY="${2}"
  LEVEL_2_KEY="${3}"

  jq -r ".binaries[] | select(.name == \"${BIN_NAME}\") | .exec.${LEVEL_1_KEY}.${LEVEL_2_KEY} | join(\"; \")" "${BIN_DATA_FILE}"
}

# ----------------------------------------- END FUNCTIONS ---------------------------------------- #

# ################################################################################################ #

# -------------------------------------- BEGIN DOWNLOAD_BIN -------------------------------------- #

# ############################################################################ #
# Displays usage of 'download::main' function.
#
# Globals:
#   __NAME
#   ARGS_SECTION
# Arguments:
#   None.
# Outputs:
#   Writes usage to stdout.
# ############################################################################ #
download::usage() {
  echo "Usage: ${__NAME} download <BINARY> <VERSION>"
  echo "Download a binary."
  echo
  echo "${ARGS_SECTION}"
}

# ############################################################################ #
# TODO:
#   define sha256sum validation.
#
# Downloads a binary and takes several actions to prepare it for usage, i.e.
# unpacking, renaming, granting permission etc.. This functions expects the
# provided arguments to be valid. It should therefore not be called by the
# executing user directly but rather by another function which conducts
# validation checks before passing the arguments.
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes all variables to stdout before downloading.
# ############################################################################ #
download::quick() {
  local BIN_NAME
  local BIN_VERSION
  local BIN_DIR

  BIN_NAME="${1}"
  BIN_VERSION="${2}"
  BIN_DIR="${BIN_PARENT_DIR}/${BIN_NAME}/v${BIN_VERSION}"

  echo "# downloading ..."
  echo "BIN_NAME    : ${BIN_NAME}"
  echo "BIN_VERSION : ${BIN_VERSION}"
  echo "BIN_DIR     : ${BIN_DIR}"

  mkdir -p "${BIN_DIR}"
  cd "${BIN_DIR}"
  rm -rf "./"*

  echo
  eval "$(get_exec "${BIN_NAME}" "download" "binary")"

  chmod +x "${BIN_NAME}"
  find "." -not -name "${BIN_NAME}" -delete
}

# ############################################################################ #
# Calls 'download::quick' if the following checks are succesfully passed:
# - the binary name is valid (see 'bin_name_is_valid').
# - the binary version is valid (see 'bin_version_is_valid').
# - the binary does not already exist locally (see 'bin_exists_locally').
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes an info message to stdout if the following occurs:
#   - the binary already exists locally.
#   Writes an error message to stdout if one of the following occurs:
#   - the binary name is invalid.
#   - the binary version is invalid.
# ############################################################################ #
download::main() {
  local BIN_NAME
  local BIN_VERSION

  BIN_NAME="${1}"
  BIN_VERSION="${2}"

  if [[ "${BIN_NAME}" == "help" ]]; then
    download::usage
    exit
  elif ! bin_name_is_valid "${BIN_NAME}"; then
    echo "${__NAME}: download: binary name '${BIN_NAME}' is invalid. See '${__NAME} download help'."
    exit 1
  elif ! bin_version_is_valid "${BIN_VERSION}"; then
    echo "${__NAME}: download: binary version '${BIN_VERSION}' is invalid. See '${__NAME} download help'."
    exit 1
  fi

  if bin_exists_locally "${BIN_NAME}" "${BIN_VERSION}"; then
    echo "${__NAME}: download: binary '${BIN_NAME}' at version '${BIN_VERSION}' already exists on your machine."
  else
    download::quick "${BIN_NAME}" "${BIN_VERSION}"
  fi
}

# --------------------------------------- END DOWNLOAD_BIN --------------------------------------- #

# ################################################################################################ #

# --------------------------------------- BEGIN INSTALL_BIN -------------------------------------- #

# ############################################################################ #
# Displays usage of 'install::main' function.
#
# Globals:
#   __NAME
#   ARGS_SECTION
# Arguments:
#   None.
# Outputs:
#   Writes usage to stdout.
# ############################################################################ #
install::usage() {
  echo "Usage: ${__NAME} install <BINARY> <VERSION>"
  echo "Install a binary."
  echo
  echo "${ARGS_SECTION}"
}

# ############################################################################ #
# Calls 'download::quick' and/or 'link::quick'
# if the following checks are succesfully passed:
# - the binary name is valid (see 'bin_name_is_valid').
# - the binary version is valid (see 'bin_version_is_valid').
# - the binary does not already exist locally (see 'bin_exists_locally').
# - the binary is not already linked (see 'bin_is_linked').
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes a blank line to stdout to increase readability.
#   Writes info messages to stdout for each of the following if they occur:
#   - the binary already exists locally.
#   - the binary is already linked.
#   Writes an error message to stdout if one of the following occurs:
#   - the binary name is invalid.
#   - the binary version is invalid.
# ############################################################################ #
install::main() {
  local BIN_NAME
  local BIN_VERSION

  BIN_NAME="${1}"
  BIN_VERSION="${2}"

  if [[ "${BIN_NAME}" == "help" ]]; then
    install::usage
    exit
  elif ! bin_name_is_valid "${BIN_NAME}"; then
    echo "${__NAME}: install: binary name '${BIN_NAME}' is invalid. See '${__NAME} install help'."
    exit 1
  elif ! bin_version_is_valid "${BIN_VERSION}"; then
    echo "${__NAME}: install: binary version '${BIN_VERSION}' is invalid. See '${__NAME} install help'."
    exit 1
  fi

  if bin_exists_locally "${BIN_NAME}" "${BIN_VERSION}"; then
    echo "${__NAME}: install: binary '${BIN_NAME}' at version '${BIN_VERSION}' already exists on your machine."
  else
    download::quick "${BIN_NAME}" "${BIN_VERSION}"
  fi

  if bin_is_linked "${BIN_NAME}" "${BIN_VERSION}"; then
    echo "${__NAME}: install: binary '${BIN_NAME}' at version '${BIN_VERSION}' is already linked."
  else
    echo
    link::quick "${BIN_NAME}" "${BIN_VERSION}"
  fi
}

# ---------------------------------------- END INSTALL_BIN --------------------------------------- #

# ################################################################################################ #

# ---------------------------------------- BEGIN LINK_BIN ---------------------------------------- #

# ############################################################################ #
# Displays usage of 'link::main' function.
#
# Globals:
#   __NAME
#   ARGS_SECTION
# Arguments:
#   None.
# Outputs:
#   Writes usage to stdout.
# ############################################################################ #
link::usage() {
  echo "Usage: ${__NAME} link <BINARY> <VERSION>"
  echo "Link a binary."
  echo
  echo "${ARGS_SECTION}"
}

# ############################################################################ #
# Links a binary. This functions expects the provided arguments to be valid.
# It should therefore not be called by the executing user directly but rather
# by another function which conducts validation checks before passing the
# arguments.
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes all variables to stdout before linking.
# ############################################################################ #
link::quick() {
  local BIN_NAME
  local BIN_VERSION
  local BIN_TARGET
  local BIN_LINK

  BIN_NAME="${1}"
  BIN_VERSION="${2}"
  BIN_TARGET="${BIN_PARENT_DIR}/${BIN_NAME}/v${BIN_VERSION}/${BIN_NAME}"
  BIN_LINK="${BIN_LINK_DIR}/${BIN_NAME}"

  echo "# linking ..."
  echo "BIN_NAME    : ${BIN_NAME}"
  echo "BIN_VERSION : ${BIN_VERSION}"
  echo "BIN_TARGET  : ${BIN_TARGET}"
  echo "BIN_LINK    : ${BIN_LINK}"

  ln -fs  "${BIN_TARGET}" "${BIN_LINK}"
}

# ############################################################################ #
# Calls 'link::quick' if the following checks are succesfully passed:
# - the binary name is valid (see 'bin_name_is_valid').
# - the binary version is valid (see 'bin_version_is_valid').
# - the binary is not already linked (see 'bin_is_linked').
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes an info message to stdout if the following occurs:
#   - the binary is already linked.
#   Writes an error message to stdout if one of the following occurs:
#   - the binary name is invalid.
#   - the binary version is invalid.
# ############################################################################ #
link::main() {
  local BIN_NAME
  local BIN_VERSION

  BIN_NAME="${1}"
  BIN_VERSION="${2}"

  if [[ "${BIN_NAME}" == "help" ]]; then
    link::usage
    exit
  elif ! bin_name_is_valid "${BIN_NAME}"; then
    echo "${__NAME}: link: binary name '${BIN_NAME}' is invalid. See '${__NAME} link help'."
    exit 1
  elif ! bin_version_is_valid "${BIN_VERSION}"; then
    echo "${__NAME}: link: binary version '${BIN_VERSION}' is invalid. See '${__NAME} link help'."
    exit 1
  fi

  if bin_is_linked "${BIN_NAME}" "${BIN_VERSION}"; then
    echo "${__NAME}: link: binary '${BIN_NAME}' at version '${BIN_VERSION}' is already linked."
  else
    link::quick "${BIN_NAME}" "${BIN_VERSION}"
  fi
}

# ----------------------------------------- END LINK_BIN ----------------------------------------- #

# ################################################################################################ #

# --------------------------------------- BEGIN REMOVE_BIN --------------------------------------- #

# ############################################################################ #
# Displays usage of 'remove::main' function.
#
# Globals:
#   __NAME
#   ARGS_SECTION
# Arguments:
#   None.
# Outputs:
#   Writes usage to stdout.
# ############################################################################ #
remove::usage() {
  echo "Usage: ${__NAME} remove <BINARY> <VERSION>"
  echo "Remove a binary."
  echo
  echo "${ARGS_SECTION}"
}

# ############################################################################ #
# Removes a binary. This functions expects the provided arguments to be valid.
# It should therefore not be called by the executing user directly but rather
# by another function which conducts validation checks before passing the
# arguments.
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes all variables to stdout before removing.
# ############################################################################ #
remove::quick() {
  local BIN_NAME
  local BIN_VERSION
  local BIN_DIR

  BIN_NAME="${1}"
  BIN_VERSION="${2}"
  BIN_DIR="${BIN_PARENT_DIR}/${BIN_NAME}/v${BIN_VERSION}"

  echo "# removing ..."
  echo "BIN_NAME    : ${BIN_NAME}"
  echo "BIN_VERSION : ${BIN_VERSION}"
  echo "BIN_DIR     : ${BIN_DIR}"

  rm -rf "${BIN_DIR}"
}

# ############################################################################ #
# Calls 'remove::quick' if the following checks are succesfully passed:
# - the binary name is valid (see 'bin_name_is_valid').
# - the binary version is valid (see 'bin_version_is_valid').
# - the binary does exist locally (see 'bin_exists_locally').
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes an info message to stdout if the following occurs:
#   - the binary does not exist locally.
#   Writes an error message to stdout if one of the following occurs:
#   - the binary name is invalid.
#   - the binary version is invalid.
# ############################################################################ #
remove::main() {
  local BIN_NAME
  local BIN_VERSION

  BIN_NAME="${1}"
  BIN_VERSION="${2}"

  if [[ "${BIN_NAME}" == "help" ]]; then
    remove::usage
    exit
  elif ! bin_name_is_valid "${BIN_NAME}"; then
    echo "${__NAME}: remove: binary name '${BIN_NAME}' is invalid. See '${__NAME} remove help'."
    exit 1
  elif ! bin_version_is_valid "${BIN_VERSION}"; then
    echo "${__NAME}: remove: binary version '${BIN_VERSION}' is invalid. See '${__NAME} remove help'."
    exit 1
  fi

  if bin_exists_locally "${BIN_NAME}" "${BIN_VERSION}"; then
    remove::quick "${BIN_NAME}" "${BIN_VERSION}"
  else
    echo "${__NAME}: remove: binary '${BIN_NAME}' at version '${BIN_VERSION}' does not exist on your machine."
  fi
}

# ---------------------------------------- END REMOVE_BIN ---------------------------------------- #

# ################################################################################################ #

# -------------------------------------- BEGIN UNINSTALL_BIN ------------------------------------- #

# ############################################################################ #
# Displays usage of 'uninstall::main' function.
#
# Globals:
#   __NAME
#   ARGS_SECTION
# Arguments:
#   None.
# Outputs:
#   Writes usage to stdout.
# ############################################################################ #
uninstall::usage() {
  echo "Usage: ${__NAME} uninstall <BINARY> <VERSION>"
  echo "Uninstall a binary."
  echo
  echo "${ARGS_SECTION}"
}

# ############################################################################ #
# Calls 'remove::quick' and/or 'unlink::quick'
# if the following checks are succesfully passed:
# - the binary name is valid (see 'bin_name_is_valid').
# - the binary version is valid (see 'bin_version_is_valid').
# - the binary does exist locally (see 'bin_exists_locally').
# - the binary is linked (see 'bin_is_linked').
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes a blank line to stdout to increase readability.
#   Writes info messages to stdout for each of the following if they occur:
#   - the binary does not exist locally.
#   - the binary is not linked.
#   Writes an error message to stdout if one of the following occurs:
#   - the binary name is invalid.
#   - the binary version is invalid.
# ############################################################################ #
uninstall::main() {
  local BIN_NAME
  local BIN_VERSION

  BIN_NAME="${1}"
  BIN_VERSION="${2}"

  if [[ "${BIN_NAME}" == "help" ]]; then
    uninstall::usage
    exit
  elif ! bin_name_is_valid "${BIN_NAME}"; then
    echo "${__NAME}: uninstall: binary name '${BIN_NAME}' is invalid. See '${__NAME} uninstall help'."
    exit 1
  elif ! bin_version_is_valid "${BIN_VERSION}"; then
    echo "${__NAME}: uninstall: binary version '${BIN_VERSION}' is invalid. See '${__NAME} uninstall help'."
    exit 1
  fi

  if bin_exists_locally "${BIN_NAME}" "${BIN_VERSION}"; then
    remove::quick "${BIN_NAME}" "${BIN_VERSION}"
  else
    echo "${__NAME}: uninstall: binary '${BIN_NAME}' at version '${BIN_VERSION}' does not exist on your machine."
  fi

  if bin_is_linked "${BIN_NAME}" "${BIN_VERSION}"; then
    echo
    unlink::quick "${BIN_NAME}" "${BIN_VERSION}"
  else
    echo "${__NAME}: uninstall: binary '${BIN_NAME}' at version '${BIN_VERSION}' is not linked."
  fi
}

# --------------------------------------- END UNINSTALL_BIN -------------------------------------- #

# ################################################################################################ #

# --------------------------------------- BEGIN UNLINK_BIN --------------------------------------- #

# ############################################################################ #
# Displays usage of 'unlink::main' function.
#
# Globals:
#   __NAME
#   ARGS_SECTION
# Arguments:
#   None.
# Outputs:
#   Writes usage to stdout.
# ############################################################################ #
unlink::usage() {
  echo "Usage: ${__NAME} unlink <BINARY> <VERSION>"
  echo "Unlink a binary."
  echo
  echo "${ARGS_SECTION}"
}

# ############################################################################ #
# Unlinks a binary. This functions expects the provided arguments to be valid.
# It should therefore not be called by the executing user directly but rather
# by another function which conducts validation checks before passing the
# arguments.
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes all variables to stdout before unlinking.
# ############################################################################ #
unlink::quick() {
  local BIN_NAME
  local BIN_VERSION
  local BIN_TARGET
  local BIN_LINK

  BIN_NAME="${1}"
  BIN_VERSION="${2}"
  BIN_TARGET="${BIN_PARENT_DIR}/${BIN_NAME}/v${BIN_VERSION}/${BIN_NAME}"
  BIN_LINK="${BIN_LINK_DIR}/${BIN_NAME}"

  echo "# unlinking ..."
  echo "BIN_NAME    : ${BIN_NAME}"
  echo "BIN_VERSION : ${BIN_VERSION}"
  echo "BIN_TARGET  : ${BIN_TARGET}"
  echo "BIN_LINK    : ${BIN_LINK}"

  rm -f "${BIN_LINK}"
}

# ############################################################################ #
# Calls 'unlink::quick' if the following checks are succesfully passed:
# - the binary name is valid (see 'bin_name_is_valid').
# - the binary version is valid (see 'bin_version_is_valid').
# - the binary is linked (see 'bin_is_linked').
#
# Globals:
#   __NAME
# Arguments:
#   1 - binary name.
#   2 - binary version (SemVer).
# Outputs:
#   Writes an info message to stdout if the following occurs:
#   - the binary is not linked.
#   Writes an error message to stdout if one of the following occurs:
#   - the binary name is invalid.
#   - the binary version is invalid.
# ############################################################################ #
unlink::main() {
  local BIN_NAME
  local BIN_VERSION

  BIN_NAME="${1}"
  BIN_VERSION="${2}"

  if [[ "${BIN_NAME}" == "help" ]]; then
    unlink::usage
    exit
  elif ! bin_name_is_valid "${BIN_NAME}"; then
    echo "${__NAME}: unlink: binary name '${BIN_NAME}' is invalid. See '${__NAME} unlink help'."
    exit 1
  elif ! bin_version_is_valid "${BIN_VERSION}"; then
    echo "${__NAME}: unlink: binary version '${BIN_VERSION}' is invalid. See '${__NAME} unlink help'."
    exit 1
  fi

  if bin_is_linked "${BIN_NAME}" "${BIN_VERSION}"; then
    unlink::quick "${BIN_NAME}" "${BIN_VERSION}"
  else
    echo "${__NAME}: unlink: binary '${BIN_NAME}' at version '${BIN_VERSION}' is not linked."
  fi
}

# ---------------------------------------- END UNLINK_BIN ---------------------------------------- #

# ################################################################################################ #

# ------------------------------------------ BEGIN MAIN ------------------------------------------ #

# ############################################################################ #
# Displays usage of 'main' function.
#
# Globals:
#   __NAME
# Arguments:
#   None.
# Outputs:
#   Writes usage to stdout.
# ############################################################################ #
usage() {
  echo "Usage: ${__NAME} <COMMAND> <ARGS>"
  echo "Manage binaries."
  echo
  echo "Commands:"
  echo "  download     see 'bin download help'."
  echo "  install      see 'bin install help'."
  echo "  link         see 'bin link help'."
  echo "  remove       see 'bin remove help'."
  echo "  uninstall    see 'bin uninstall help'."
  echo "  unlink       see 'bin unlink help'."
}

# ############################################################################ #
# Determines the provided command and calls the corresponding sub-functions.
#
# Globals:
#   __NAME
# Arguments:
#   $@
# Outputs:
#   Writes an error message to stdout if one of the following occurs:
#   - the command is unknown.
# ############################################################################ #
main() {
  err::on
  init

  case "${1}" in
    "help")
      usage
    ;;
    
    "download")
      shift 1
      download::main "$@"
    ;;

    "install")
      shift 1
      install::main "$@"
    ;;

    "link")
      shift 1
      link::main "$@"
    ;;

    "remove")
      shift 1
      remove::main "$@"
    ;;

    "uninstall")
      shift 1
      uninstall::main "$@"
    ;;

    "unlink")
      shift 1
      unlink::main "$@"
    ;;

    *)
      echo "${__NAME}: command '${1}' is unknown. See '${__NAME} help'."
      exit 1
    ;;
  esac
}

# ------------------------------------------- END MAIN ------------------------------------------- #

main "$@"
