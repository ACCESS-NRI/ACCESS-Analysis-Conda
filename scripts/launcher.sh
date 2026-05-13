#!/usr/bin/env bash

function in_array() {
    ### Assumes first n-1 args are an array and final arg is the string to search for
    ### Necessary because [[ libab =~ liba ]] returns true
    declare -a allargs=( "$@" )
    finalarg=${allargs[$(( ${#allargs[@]} - 1 ))]}
    for (( j=0; j<$(( ${#allargs[@]} - 1 )); j++ )); do
        [[ "${allargs[$j]}" == "${finalarg}" ]] && return 0
    done
    return 1
}

function debug_print() {
    echo "$@" 1>&2
}

if [[ "${CMS_CONDA_DEBUG_SCRIPTS}" ]]; then
    debug=debug_print
else
    debug=true
fi

### Detect if being sourced (e.g. by VSCode for environment activation)
being_sourced=false
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && being_sourced=true

wrapper_path=$( realpath "${BASH_SOURCE[0]:-${0}}" )
wrapper_bin=${wrapper_path%/*}
$debug "wrapper_bin = " "${wrapper_bin}"
conf_file="${wrapper_bin}"/launcher_conf.sh
$debug "conf_file = " "${conf_file}"

source "${conf_file}"

### Add some complicated arguments that are never meant to be used by humans
declare -a PROG_ARGS=()
while [[ $# -gt 0 ]]; do
    case "${1}" in 
        "--cms_singularity_overlay_path_override")
            ### Sometimes we do not want to use the 'correct' container
            export CONTAINER_OVERLAY_PATH_OVERRIDE=1
            $debug "cms_singularity_overlay_path_override=1"
            shift
            ;;
        "--cms_singularity_overlay_path")
            ### From time to time we need to manually specify an overlay filesystem, handle that here:
            export CONTAINER_OVERLAY_PATH="${2}"
            $debug "cms_singularity_overlay_path="${CONTAINER_OVERLAY_PATH}
            shift 2
            ;;
        "--cms_singularity_in_container_path")
            ### Set path manually
            export PATH="${2}"
            $debug "cms_singularity_in_container_path="${PATH}
            shift 2
            ;;
        "--cms_singularity_launcher_override")
            ### Override the launcher script name
            export LAUNCHER_SCRIPT="${2}"
            $debug "cms_singularity_launcher_override="${LAUNCHER_SCRIPT}
            shift 2
            ;;
        "--cms_singularity_singularity_path")
            export SINGULARITY_BINARY_PATH="${2}"
            $debug "cms_singularity_singularity_path="${SINGULARITY_BINARY_PATH}
            shift 2
            ;;
        *)
            PROG_ARGS+=( "${1}" )
            shift
            ;;
    esac
done

$debug "PROG_ARGS =" "${PROG_ARGS[@]}"

if ! [[ "${SINGULARITY_BINARY_PATH}" ]]; then
    module load singularity
    export SINGULARITY_BINARY_PATH=$( type -p singularity )
fi

[[ "${LAUNCHER_SCRIPT}" ]] || export LAUNCHER_SCRIPT="${0%/*}"/launcher.sh

### Allow invoking launcher directly with arbitrary commands
if [[ "${0}" == "${LAUNCHER_SCRIPT}" ]]; then
    ### Assume "$1" and onwards is the command to run
    cmd_to_run=( "${PROG_ARGS[@]}" )
else
    cmd_to_run=( "${0}" )
    cmd_to_run+=( "${PROG_ARGS[@]}" )
fi

$debug "cmd_to_run = " "${cmd_to_run[@]}"

### Handle the case where we've been invoked directly. Make sure the container
### we need is on path, and that CONDA_BASE is set so that the right thing
### runs in the container. If we haven't been directly invoked, this does
### nothing - Unless told otherwise
###
### Reminder: The --overlay argument that appears LAST takes priority, so put the
### default container first, that way if we're intentionally trying to use it from
### somewhere else (e.g. jobfs), the one on gdata will be mounted but not used.
myenv=$( basename "${wrapper_bin%/*}" ".d" )
if ! [[ "${CONTAINER_OVERLAY_PATH_OVERRIDE}" ]]; then
    if ! [[ :"${CONTAINER_OVERLAY_PATH}": =~ :"${CONDA_BASE_ENV_PATH}"/envs/"${myenv}".sqsh: ]]; then
        [[ -r "${CONDA_BASE_ENV_PATH}"/envs/"${myenv}".sqsh ]] && export CONTAINER_OVERLAY_PATH="${CONDA_BASE_ENV_PATH}"/envs/"${myenv}".sqsh:${CONTAINER_OVERLAY_PATH}
    fi
fi

$debug "CONTAINER_OVERLAY_PATH after override check = " ${CONTAINER_OVERLAY_PATH}

export CONDA_BASE="${CONDA_BASE_ENV_PATH}/envs/${myenv}"

if ! [[ "${being_sourced}" ]] && ! [[ -x "${SINGULARITY_BINARY_PATH}" ]]; then
    ### Short circuit detection
    ### In some cases (e.g. mpi processes launched from orterun), launcher will be invoked from
    ### within the container. The tell-tale sign for this is if /opt/singularity is missing.
    ### The only way this can happen is if we've tried to run something that has come
    ### from the bin directory in scripts/env.d/bin/ - the only place these can come from is the
    ### bin directory of the active conda env, so just reset the path to that but keep the 
    ### original argv[0] so virtual envs work.
    cmd_to_run[0]="${CONDA_BASE}/bin/${cmd_to_run[0]##*/}"
    $debug "Short circuit detected, running: " "exec -a" "${0}" "${cmd_to_run[@]}"
    exec -a "${0}" "${cmd_to_run[@]}"
fi

### Handle some functions separately.
if [[ -e ${wrapper_bin}/../overrides/"${cmd_to_run[0]##*/}".sh ]]; then
    $debug "Running override function: " ${wrapper_bin}/../overrides/"${cmd_to_run[0]##*/}".sh "${cmd_to_run[@]:1}"
    exec ${wrapper_bin}/../overrides/"${cmd_to_run[0]##*/}".sh "${cmd_to_run[@]:1}"
fi

### Add some additional config for some functions
if [[ -e "${wrapper_bin}"/../overrides/"${cmd_to_run[0]##*/}".config.sh ]]; then
    $debug "Loading additional configuration: " "${wrapper_bin}"/../overrides/"${cmd_to_run[0]##*/}".config.sh
    . "${wrapper_bin}"/../overrides/"${cmd_to_run[0]##*/}".config.sh
fi

export SINGULARITYENV_LD_LIBRARY_PATH=$LD_LIBRARY_PATH
### Ensure key geospatial data paths are always available inside the container,
### including interactive shells launched via launcher.sh bash.
export SINGULARITYENV_PROJ_DATA="${CONDA_BASE}/share/proj"
export SINGULARITYENV_GDAL_DATA="${CONDA_BASE}/share/gdal"
declare -a singularity_default_path=( '/usr/local/sbin' '/usr/local/bin' '/usr/sbin' '/usr/bin' '/sbin' '/bin' )

while IFS= read -r -d: i; do
    in_array "${singularity_default_path[@]}" "${i}" && continue
    [[ "${i}" == "/opt/singularity/bin" ]] && continue
    [[ "${i}" == "${wrapper_bin}" ]] && continue
    SINGULARITYENV_PREPEND_PATH="${SINGULARITYENV_PREPEND_PATH}:${i}"
done<<<"${PATH%:}:"
export SINGULARITYENV_PREPEND_PATH=${SINGULARITYENV_PREPEND_PATH#:*}

$debug "SINGULARITYENV_PREPEND_PATH= " ${SINGULARITYENV_PREPEND_PATH}

overlay_args=""
while IFS= read -r -d: i; do
    overlay_args="${overlay_args}--overlay=${i} "
done<<<"${CONTAINER_OVERLAY_PATH%:}:"

$debug "overlay_args= " ${overlay_args}

bind_str=""
for bind_dir in "${bind_dirs[@]}"; do
    [[ -d "${bind_dir}" ]] && bind_str="${bind_str}${bind_dir},"
done
bind_str=${bind_str%,}

$debug "binding args= " ${bind_str}

if [[ "${being_sourced}" ]]; then
    ### Sourced activation is used by VSCode. Keep this path non-interactive and
    ### avoid shell replacement. Set key runtime vars needed by common geospatial
    ### libraries and return control to the caller.
    ### NOTE: CONDA_BASE paths live inside the squashfs overlay and don't exist on
    ### the host filesystem, so we must NOT guard these with -d checks. The paths
    ### are valid inside the singularity container where python actually runs.
    $debug "Being sourced - applying non-interactive activation environment"

    export PROJ_DATA="${CONDA_BASE}/share/proj"
    export GDAL_DATA="${CONDA_BASE}/share/gdal"

    return 0
fi

$debug "Singularity invocation: " "$SINGULARITY_BINARY_PATH" -s exec --bind "${bind_str}" ${overlay_args} "${CONTAINER_PATH}" "${cmd_to_run[@]}"
"$SINGULARITY_BINARY_PATH" -s exec --bind "${bind_str}" ${overlay_args} "${CONTAINER_PATH}" "${cmd_to_run[@]}"
