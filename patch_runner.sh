#!/bin/bash
#
# This script is ment to be used to run every database patch for the system in
# order to register them for accounting information and automatic handling.

# Imports ---------------------------------------------------------------------
scriptDir="$(cd "$(dirname "${0}")"; pwd)"
. "${scriptDir}/lib-logging.sh"
#------------------------------------------------------------------------------

# Configuration [start] -------------------------------------------------------
DEBUG=0
LOG_FILE=/tmp/patch_runner.log
LOG_MSG_DATE_SPEC='%H:%M:%S'
PATCHES_SOURCE=${PWD}
DBVARIABLES_FILE="${scriptDir}/dbvariables.sh"
# Configuration [ end ] -------------------------------------------------------

# Globals [start] -------------------------------------------------------------
DECLARED_CONNECTIONS=()
# Globals [ end ] -------------------------------------------------------------

# Test and run DB variables script [start] ------------------------------------
if [ ! -x "${DBVARIABLES_FILE}" ]; then
  log_err -n "File '${DBVARIABLES_FILE}' MUST EXIST and be EXECUTABLE."
  exit -1
fi
. "${DBVARIABLES_FILE}"
# Test and run DB variables script [ end ] ------------------------------------

# Function "add_patch" [start] ------------------------------------------------
#   Arguments:
#   	$1 = patch name
#   	$2 = patch source
#   Returns: psql return value.
function add_patch(){
  local name=${1}
  local src=${2}

  [ ${DEBUG} -ne 0 ] && \
  	log_debug "Adding patch '${patch_name}' to the database."

  store_pgpass_away
  echo "${PG_PATCHMANAGER}" >> ~/.pgpass

  local msg=$(echo "INSERT INTO environmentpatch (patch, source) VALUES ('${name}','${src}')" | \
  	psql -h${PG_PATCHMANAGER_DB_HOST} -p${PG_PATCHMANAGER_DB_PORT} \
  	-U${PG_PATCHMANAGER_DB_USER} ${PG_PATCHMANAGER_DB} --tuples-only 2>&1)
  local rv=${?}
  [ ${rv} -ne 0 -o "${msg:0:7}" == "ERROR: " \
  	-o "${msg:0:13}" == "psql: FATAL: " ] && restore_original_pgpass && \
  	log_err "${msg}" && return -1

  # This assumes nobody other than this single running instance of patch_runner
  # is inserting anything. Also assumes time travel hasn't been invented yet...
  local msg=$(echo "SELECT executiontime FROM environmentpatch WHERE patch = '${name}' AND source = '${src}' AND status = 0 ORDER BY executiontime DESC LIMIT 1" | \
  	psql -h${PG_PATCHMANAGER_DB_HOST} -p${PG_PATCHMANAGER_DB_PORT} \
  	-U${PG_PATCHMANAGER_DB_USER} ${PG_PATCHMANAGER_DB} --tuples-only 2>&1)
  local rv=${?}

  restore_original_pgpass

  [ "${msg:0:7}" == "ERROR: " -o "${msg:0:13}" == "psql: FATAL: " ] && \
  	log_err "${msg}" && return -1

  echo "${msg}" | sed -e 's/^ *//' -e 's/ *$//'
  return ${rv}
}
# Function "add_patch" [ end ] ------------------------------------------------

# Function "commit_all" [start] -----------------------------------------------
#   Arguments:
#   	$1 = base name
#   Returns: psql return value.
function commit_all(){
  local base_name=${1}

  [ ${DEBUG} -ne 0 ] && log_debug "Committing all transactions '${base_name}'."

  # Unpack all declared connections and commit one by one
  local let errors=0
  for conn in "${DECLARED_CONNECTIONS[@]}"; do
    local pass=${conn#*:} # port:db:user:pass
    local port=${pass%%:*}
    pass=${pass#*:} # db:user:pass
    local db=${pass%%:*}
    pass=${pass#*:} # user:pass
    local user=${pass%%:*}
    pass=${pass#*:}
    local host=${conn%%:*}
    commit_transaction "${base_name}" "${host}" "${port}" "${db}" "${user}" \
    	"${pass}" || let ++errors
  done

  return ${errors}
}
# Function "commit_all" [ end ] -----------------------------------------------

# Function "commit_transaction" [start] ---------------------------------------
#   Arguments:
#       $1 = name of the transaction
#       $2 = host
#       $3 = port
#       $4 = db
#       $5 = user
#       $6 = pass
function commit_transaction(){
  local name=${1}
  local host=${2}
  local port=${3}
  local db=${4}
  local user=${5}
  local pass=${6}

  store_pgpass_away
  echo "${host}:${port}:${db}:${pass}" >> ~/.pgpass

  local result=$(echo "SELECT gid FROM pg_prepared_xacts WHERE gid LIKE '${name} (%)' AND database = '${db}'" | \
  	psql -h${host} -p${port} -U${user} ${db} --tuples-only 2>&1 | \
  	sed -e 's/^[\t ]*//g' -e 's/[\t ]*$//g')
  if [ ${?} -ne 0 -o "${result:0:7}" == "ERROR: " -o \
  	"${result:0:13}" == "psql: FATAL: " ]; then
    restore_original_pgpass
    return -1
  fi

  local bakIFS=${IFS}
  IFS='
'
  local commit_prepared='';
  for transaction in ${result}; do
    commit_prepared="${commit_prepared} COMMIT PREPARED '${transaction}';"
  done
  result=$(echo "${commit_prepared}" | \
  	psql -h${host} -p${port} -U${user} ${db} --tuples-only 2>&1)
  rv=${?}
  IFS=${bakIFS}

  restore_original_pgpass

  if [ ${rv} -ne 0 -o "${result:0:7}" == "ERROR: " \
  	-o "${result:0:13}" == "psql: FATAL: " ]; then
    log_err "${result}"
    return -1
  fi
  return 0;
}
# Function "commit_transaction" [ end ] ---------------------------------------

# Function "restore_original_pgpass" [start] ----------------------------------
function restore_original_pgpass(){
  if [ -e ~/.pgpass.patch_runner.$$.bak ]; then
    mv ~/.pgpass.patch_runner.$$.bak ~/.pgpass
    exit_on_error "Could NOT restore file ~/.pgpass from ~/.pgpass.patch_runner.$$.bak."
  else
    rm ~/.pgpass
    exit_on_error 'Could NOT remove temporary file ~/.pgpass.'
  fi
}
# Function "restore_original_pgpass" [ end ] ----------------------------------

# Function "run_patch" [start] ------------------------------------------------
#   Arguments:
#   	$1 = patch name
#   	$1 = patch status
#   Sets: Global variable 
#   Returns: PostgreSQL return value for the applied patch.
function run_patch(){
  local patch=${1}
  local let last_status=${2}

  store_pgpass_away

  export PATCH_RUNNER_PATCH_STATUS=${last_status}
  export PATCH_RUNNER_PATCH_NAME=${patch}
  local output=$(
  	function onExit(){
  	  rv=${1:-${?}};
  	  for conn in "${DECLARED_CONNECTIONS[@]}"; do echo "${conn}"; done;
  	  echo ${#DECLARED_CONNECTIONS[*]}
  	  echo ${rv};
  	};
  	trap onExit SIGHUP SIGINT SIGQUIT SIGKILL SIGSEGV SIGTERM EXIT;
  	. ${patch} > /dev/null
  );
  local rv=$(echo "${output}" | tail -1)
  local nconn=$(echo "${output}" | tail -2 | head -1)
  # Just head because patch's output is going to /dev/null
  DECLARED_CONNECTIONS=($(echo -n "${output}"|head -$((${nconn}))|grep '.'))

  restore_original_pgpass

  return ${rv}
}
# Function "run_patch" [ end ] ------------------------------------------------

# Function "store_pgpass_away" [start] ----------------------------------------
function store_pgpass_away(){
  local moved=0
  if [ -e ~/.pgpass ]; then
    mv ~/.pgpass ~/.pgpass.patch_runner.$$.bak
    exit_on_error 'Could NOT move file ~/.pgpass away.'
  fi
  if ! touch ~/.pgpass; then
    log_err 'Could NOT create file ~/.pgpass.'
    if [ ${moved} -ne 0 ]; then
      mv ~/.pgpass.patch_runner.$$.bak ~/.pgpass
      exit_on_error "Could NOT restore file ~/.pgpass from ~/.pgpass.patch_runner.$$.bak."
    fi
  fi
  if ! chmod 600 ~/.pgpass; then
    log_err 'Could NOT change permissions to file ~/.pgpass.'
    if [ ${moved} -ne 0 ]; then
      mv ~/.pgpass.patch_runner.$$.bak ~/.pgpass
      exit_on_error "Could NOT restore file ~/.pgpass from ~/.pgpass.patch_runner.$$.bak."
    else
      rm ~/.pgpass
      exit_on_error 'Could NOT remove temporary file ~/.pgpass.'
    fi
  fi
}
# Function "store_pgpass_away" [ end ] ----------------------------------------

# Function "get_patch_status" [start] -----------------------------------------
#   Arguments:
#   	$1 = patch name
#   Outputs: the execution time of the patch.
#   Returns: the status of the patch.
function get_patch_status(){
  local name=${1}

  if [ ${DEBUG} -ne 0 ]; then log_debug "Getting ${name} status."; fi

  store_pgpass_away
  echo "${PG_PATCHMANAGER}" >> ~/.pgpass

  # This assumes that there is only one row for the patch having a status other
  # than 2.
  local result=$(echo "SELECT status, executiontime FROM environmentpatch WHERE patch = '${name}' ORDER BY executiontime DESC LIMIT 1" | \
  	psql -h${PG_PATCHMANAGER_DB_HOST} -p${PG_PATCHMANAGER_DB_PORT} \
  	-U${PG_PATCHMANAGER_DB_USER} ${PG_PATCHMANAGER_DB} --tuples-only 2>&1)
  local last_status=${result%%|*}
  local execution_time=${result##*|}

  restore_original_pgpass

  echo "${execution_time}" | sed -e 's/^ *//' -e 's/ *$//'
  return ${last_status// /}
}
# Function "get_patch_status" [ end ] -----------------------------------------

# Function "decide_rerun" [start] ---------------------------------------------
#   Arguments:
#   	$1 = patch_name
#   	$2 = patch_host
#   Returns: 0 if will rerun, -1 if not.
function decide_rerun(){
  local state=${?}
  if [ ${state} -eq 2 ]; then
    local response='rubbish'
    if [ ${rv} -eq 1 ]; then
      echo -n 'Patch has already been run on this server. '
      echo -n 'Want to run it again? (y/N): '
    else
      echo -n 'Want to run the patch anyway? (y/N): '
    fi
    while [ "${response}" == "rubbish" ]; do
      read response
      if [ "${response}" == "y" -o "${response}" == "Y" ]; then
        [ ${DEBUG} -ne 0 ] && log_debug 'Will re-run patch.'
      elif [ "${response}" == "n" -o "${response}" == "N" -o \
      	"${response}" == "" ]; then
        echo 'No'
        [ ${DEBUG} -ne 0 ] && log_debug 'Aborted by user...'
        return -1
      else
        response='rubbish'
        echo -n 'Stop fooling around. (y/N)?: '
      fi
    done
  fi
  return 0
}
# Function "decide_rerun" [ end ] ---------------------------------------------

# Function "set_patch_status" [start] -----------------------------------------
#   Arguments:
#   	$1 = patch name
#   	$2 = execution time
#       $3 = new status
#   Returns: psql return value.
function set_patch_status(){
  [ ${DEBUG} -ne 0 ] && log_debug "Setting patch status to ${3}."

  store_pgpass_away
  echo "${PG_PATCHMANAGER}" >> ~/.pgpass

  local msg=$(echo "UPDATE environmentpatch SET status='${3}' WHERE patch='${1}' AND executiontime='${2}'" | \
  	psql -h${PG_PATCHMANAGER_DB_HOST} -p${PG_PATCHMANAGER_DB_PORT} \
  	-U${PG_PATCHMANAGER_DB_USER} ${PG_PATCHMANAGER_DB} --tuples-only 2>&1)

  restore_original_pgpass
}
# Function "set_patch_status" [ end ] -----------------------------------------

# Function "main" [start] -----------------------------------------------------
#   Arguments: (checking for 1 only)
#   	$1 = patch_file
#   Returns: 0 if no problem arose, 1 if no parameters,
#            -1 if patch does not exist, -2 if cannot set execution flag to
#            patch, register_patch retval if otherwise.
function main(){
  # Check parameters...
  if [ ${#} -ne 1 ]; then
    echo "Usage: ${0} <patch file>" >&2
    return 1
  fi
  if [ ! -f "${1}" ]; then
    log_err "File '${1}' does NOT exist."
    return -1;
  fi

  # Gather information...
  local patch_name=${1#./}
  [ ${DEBUG} -ne 0 ] && log_debug "Patch name: ${patch_name}"
  local patch_host=${PG_PATCHMANAGER_DB_HOST}
  [ "${patch_host}" == "localhost" ] && patch_host=$(hostname -s)
  [ ${DEBUG} -ne 0 ] && log_debug "Patch host: ${patch_host}"

  # Get status...
  local execution_time=$(get_patch_status "${patch_name}")
  local let last_status=${?}
  [ ${DEBUG} -ne 0 ] && log_debug "Last status: ${last_status}"

  if [ ${last_status} -eq 2 ]; then
    # Decide whether to re-run the patch or not.
    decide_rerun "${patch_name}" "${patch_host}" || return -1
    execution_time=$(add_patch "${patch_name}" "${PATCHES_SOURCE}")
    let last_status=0
  fi

  if [ ${last_status} -eq 0 ]; then
    [ "${execution_time}" == "" ] && \
    	execution_time=$(add_patch "${patch_name}" "${PATCHES_SOURCE}")
    # Some servers may have achieved the prepare_commit stage.
    # For the rest, we need to run the patch.
    run_patch "${patch_name}" ${last_status} || return -1
    let last_status=1
    set_patch_status "${patch_name}" "${execution_time}" ${last_status}
  fi

  if [ ${last_status} -eq 1 ]; then
    # Patch is waiting for the final commit.
    commit_all "${patch_name}" || return -1
    let last_status=2
    set_patch_status "${patch_name}" "${execution_time}" ${last_status}
  elif [ ${last_status} -ne 2 ]; then
    log_err "Current patch status (${last_status}) is not recognized."
    return -1
  fi

  return 0
}
# Function "main" [ end ] -----------------------------------------------------

main "${@}"
exit ${?}
