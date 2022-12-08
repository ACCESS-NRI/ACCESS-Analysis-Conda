#!/usr/bin/env bash

function in_array() {
    ### Assumes first n-1 args are an array and final arg is the string to search for
    ### Necessary because [[ libab =~ liba ]] returns true
    declare -a allargs=( "$@" )
    finalarg=${allargs[$(( ${#allargs[@]} - 1 ))]}
    for (( j=0; j<$(( ${#allargs[@]} - 2 )); j++ )); do
        [[ "${allargs[$j]}" == "${finalarg}" ]] && return 0
    done
    return 1
}

script=$( realpath "${0}" )
wrapper_bin=$( dirname "${script}" )
conf_file="${wrapper_bin}"/launcher_conf.sh
if ! [[ -e "${conf_file}" ]]; then
    ### Hmmm... we might be being run form a virtual env - find our real path
    conf_file=$( dirname $( realpath ${script} ) )/launcher_conf.sh
fi
source "${conf_file}"

### Add some complicated arguments that are never meant to be used by humans
declare -a PROG_ARGS=()
while [[ $# -gt 0 ]]; do
    case "${1}" in 
        "--cms_singularity_overlay_path")
            ### From time to time we need to manually specify an overlay filesystem, handle that here:
            export CONTAINER_OVERLAY_PATH="${2}"
            shift 2
            ;;
        "--cms_singularity_in_container_path")
            ### Set path manually
            export PATH="${2}"
            shift 2
            ;;
        "--cms_singularity_launcher_override")
            ### Override the launcher script name
            export LAUNCHER_SCRIPT="${2}"
            shift 2
            ;;
        *)
            PROG_ARGS+=( "${1}" )
            shift
            ;;
    esac
done

if ! [[ "${SINGULARITY_BINARY_PATH}" ]]; then
    module load singularity
    export SINGULARITY_BINARY_PATH=$( which singularity )
fi

### Allow invoking launcher directly with arbitrary commands
if [[ "${0}" == "${LAUNCHER_SCRIPT}" ]]; then
    ### Assume "$1" and onwards is the command to run
    cmd_to_run=( "${PROG_ARGS[@]}" )
else
    cmd_to_run=( "${0}" )
    cmd_to_run+=( "${PROG_ARGS[@]}" )
fi
if ! [[ -x "${SINGULARITY_BINARY_PATH}" ]]; then
    ### Short circuit detection
    ### In some cases (e.g. mpi processes launched from orterun), launcher will be invoked from
    ### within the container. The tell-tale sign for this is if /opt/singularity is missing.
    ### The only way this can happen is if we've tried to run something that has come
    ### from the bin directory in scrpits/env.d/bin/ - the only place these can come from is the
    ### bin directory of the active conda env, so just reset the path to that but keep the 
    ### original argv[0] so virtual envs work.
    cmd_to_run[0]="${CONDA_BASE}/bin/${cmd_to_run[0]##*/}"
    exec -a "${0}" "${cmd_to_run[@]}"
fi

### Handle some functions separately.
if [[ -e ${wrapper_bin}/../overrides/"${cmd_to_run[0]##*/}".sh ]]; then
    exec ${wrapper_bin}/../overrides/"${cmd_to_run[0]##*/}".sh "${cmd_to_run[@]:1}"
fi

### Add some additional config for some functions
if [[ -e "${wrapper_bin}"/../overrides/"${cmd_to_run[0]##*/}".config.sh ]]; then
    . "${wrapper_bin}"/../overrides/"${cmd_to_run[0]##*/}".config.sh
fi

export SINGULARITYENV_LD_LIBRARY_PATH=$LD_LIBRARY_PATH
declare -a singularity_default_path=( '/usr/local/sbin' '/usr/local/bin' '/usr/sbin' '/usr/bin' '/sbin' '/bin' )

while IFS= read -r -d: i; do
    in_array "${singularity_default_path[@]}" "${i}" && continue
    [[ "${i}" == "/opt/singularity/bin" ]] && continue
    [[ "${i}" == "${wrapper_bin}" ]] && continue
    SINGULARITYENV_PREPEND_PATH="${SINGULARITYENV_PREPEND_PATH}:${i}"
done<<<"${PATH%:}:"
export SINGULARITYENV_PREPEND_PATH=${SINGULARITYENV_PREPEND_PATH#:*}

overlay_args=""
while IFS= read -r -d: i; do
    overlay_args="${overlay_args}--overlay=${i} "
done<<<"${CONTAINER_OVERLAY_PATH%:}:"

"$SINGULARITY_BINARY_PATH" -s exec --bind /etc,/half-root,/local,/ram,/run,/system,/usr,/var/lib/sss,/var/run/munge ${overlay_args} /g/data/v45/dr4292/singularity/test.sif "${cmd_to_run[@]}"
