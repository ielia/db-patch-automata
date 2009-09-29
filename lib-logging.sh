#!/bin/bash
#
# Required variables:
#   * LOG_MSG_DATE_SPEC (e.g.: %H:%M:%S.)
#   * LOG_FILE.

#------------------------------------------------------------------------------
function exit_on_error() {
  exit_with_error ${?} "${1}"
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function exit_on_pipe_error() {
  local status=0
  for s in ${PIPESTATUS[*]}; do
    status=$(( ${status} | ${s} ))
  done
  exit_with_error ${status} "${1}"
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function exit_with_error() {
  local let rv=${1}
  local message="${2}"
  if [ ${rv} -ne 0 ]; then
    log_err "${message}"
    log_err 'Aborting...'
    exit ${rv}
  fi
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function log_prep() {
  local tag="${1}"

  echo -n "($(date "+${LOG_MSG_DATE_SPEC}"))"
  if [ "${tag}" != "" ]; then
    echo -n " [${tag}]"
  fi
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function log_cmd() {
  local prepend_tag="${1}"
  shift
  local prepend=$(log_prep "${prepend_tag}")
  echo "${prepend} ${@}" | tee -a "${LOG_FILE}"
  log_cmd_output "${prepend}" "${@}"
  return ${?}
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function log_cmd_no_cmdln() {
  local prepend_tag="${1}"
  shift
  local prepend=$(log_prep "${prepend_tag}")
  echo "${prepend} ${1}" | tee -a "${LOG_FILE}"
  log_cmd_output "${prepend}" "${@}"
  return ${?}
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# XXX: Find a way to improve this...
function log_cmd_output() {
  local prepend="${1}"
  shift
  exec 3>&1
  exec 4>&1
  local let prepend_out_cut=$((${#prepend}+11)) # not the best approach...
  local let prepend_err_cut=${prepend_out_cut} # not the best approach...
  local prepend_out="${prepend//\//\\/}"
  local prepend_out="${prepend//&/\\&}"
  local prepend_err="${prepend_out%]} (stderr)] " # not the best approach...
  prepend_out="${prepend_out%]} (stdout)] " # not the best approach...
  local let rv=( $( ( ( ( "${@}"; echo ${?} >&4 ) | \
  	sed -u "s/^/${prepend_out}/" | tee -a "${LOG_FILE}" | \
  		cut -b ${prepend_out_cut}- ) 2>&1 1>&3 | \
  	sed -u "s/^/${prepend_err}/" | tee -a "${LOG_FILE}" | \
  		cut -b ${prepend_err_cut}- ) 4>&1 1>&2 ) ) 3>&1
  exec 3>&-
  exec 4>&-
  return ${rv}
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function log_debug() {
  log_msg 'DEBUG' "${1}" >&2
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function log_err() {
  log_msg 'ERROR' "${1}" >&2
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function log_info() {
  log_msg 'INFO' "${1}" >&2
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function log_msg() {
  local prepend_tag="${1}"
  local message="${2}"
  echo "$(log_prep "${prepend_tag}") ${message}" | tee -a "${LOG_FILE}"
}
#------------------------------------------------------------------------------
