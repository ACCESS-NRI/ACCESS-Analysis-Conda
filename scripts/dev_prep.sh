#!/usr/bin/env bash
###
### Prepare an interactive version of the current unstable containerised conda env
### for development purposes n.b. source me

source install_config.sh
source functions.sh

_inner() {

    rm -rf "${CONDA_SCRIPT_PATH}"/"${FULLENV}".d/{bin,overrides}
    
    pushd "${ENV_INSTALLATION_PATH}"
    ### Get rid of stuff from packages we don't want
    for dir in bin lib etc libexec include; do
	    if [[ -d "${dir}" ]]; then
            pushd $dir
            for i in $( rpm -qli "${rpms_to_remove[@]}" ); do
                fn=$( basename $i )
                [[ -f $fn ]] && rm $fn
                [[ -d $fn ]] && rm -rf $fn
            done
            popd
	    fi
    done

    ### Replace things from apps
    for pkg in "${replace_from_apps[@]}"; do
        for dir in bin etc lib include; do
	        if [[ -d "${dir}" ]]; then
                pushd $dir
                apps_subdir=/apps/"${pkg}"/"${dir}"
                for i in $( find "${apps_subdir}" -type f ); do
                    fn="${i//$apps_subdir\//}"
                    [[ -e $fn ]] && rm $fn
                    [[ "${fn}" != "${fn%/*}" ]] && mkdir -p "${fn%/*}"
                    ln -s "${i}" "${fn}"
                done
                popd
	        fi
        done
    done
    popd

    ### Update any supporting infrastructure
    copy_if_changed "${SCRIPT_DIR}"/launcher.sh "${CONDA_SCRIPT_PATH}"/launcher.sh
    for override in "${SCRIPT_DIR}"/overrides/*; do
        copy_if_changed "${override}" "${CONDA_SCRIPT_PATH}"/overrides/"${override##*/}"
    done
    copy_and_replace_if_changed "${SCRIPT_DIR}"/../modules/common_v3 "${CONDA_MODULE_PATH}"/.common_v3       CONDA_BASE APPS_SUBDIR CONDA_INSTALL_BASENAME SCRIPT_SUBDIR
    copy_and_replace_if_changed "${SCRIPT_DIR}"/launcher_conf.sh     "${CONDA_SCRIPT_PATH}"/launcher_conf.sh CONDA_BASE APPS_SUBDIR CONDA_INSTALL_BASENAME

    ### Create symlink tree
    mkdir -p "${CONDA_SCRIPT_PATH}"/"${FULLENV}".d/{bin,overrides}
    cp "${CONDA_SCRIPT_PATH}"/{launcher.sh,launcher_conf.sh} "${CONDA_SCRIPT_PATH}"/"${FULLENV}".d/bin
    pushd "${CONDA_SCRIPT_PATH}"/"${FULLENV}".d/bin
    for i in $( ls "${ENV_INSTALLATION_PATH}"/bin ); do
        ln -s launcher.sh $i
    done

    ### Add in the outside commands
    for i in "${outside_commands_to_include[@]}"; do
        ln -s launcher.sh $i
    done
    popd

    ### Add in the override and config scripts
    pushd "${CONDA_SCRIPT_PATH}"/"${FULLENV}".d/overrides
    for i in ../../overrides/*; do
        ln -s ${i}
    done
    popd

}

if [[ "$#" -gt 0 ]]; then
    if [[ "${1}" == '--inner' ]]; then
        _inner
        exit 0
    fi
fi

### Stolen from Intel oneAPI
_vars_get_proc_name() {
    if [ -n "${ZSH_VERSION:-}" ] ; then
        script="$(ps -p "$$" -o comm=)"
    else
        script="$1"
        while [ -L "$script" ] ; do
            script="$(readlink "$script")"
        done
    fi
    basename -- "$script"
}

if [[ $BASH_SOURCE  == "$(_vars_get_proc_name "$0")" ]]; then
    echo "This script must be sourced"
    return 2>/dev/null || exit 1
fi

script_path=$( realpath $BASH_SOURCE )
if [[ "${script_path::3}" == "/g/" ]]; then
    echo "This script cannot be run from /g/data" && return
fi

if [[ ! "${PBS_JOBFS}" ]]; then
    echo "Must be run inside a PBS job" && return
fi

_parse_jobfs() {
    ### PBS_NCI_JOBFS var takes the form of nnnnnnXb
    multiplier=1
    tmp="${PBS_NCI_JOBFS:: -1}"
    case "${tmp: -1}" in
        ### ;& means fallthrough
        "p")
            #multiplier=1125899906842624
            multiplier=$(( $multiplier * 1024 ))
            ;&
        "t")
            multiplier=$(( $multiplier * 1024 ))
            ;&
        "g")
            multiplier=$(( $multiplier * 1024 ))
            ;&
        "m")
            multiplier=$(( $multiplier * 1024 ))
            ;&
        "k")
            multiplier=$(( $multiplier * 1024 ))
            tmp="${tmp:: -1}"
            ;;
    esac
    echo $(( $multiplier * $tmp ))
}

if [[ $(( $( _parse_jobfs ) / $PBS_NNODES )) < 107374182400 ]]; then
    echo "Minimum of 100GB/node of jobfs" && return
fi

_initialise() {
    ### Derived temp file locations
    export OVERLAY_BASE="${CONDA_TEMP_PATH}"/overlay
    export CONDA_OUTER_BASE="${OVERLAY_BASE}"/"${CONDA_BASE#/*/}"
    export ENV_INSTALLATION_PATH="${CONDA_TEMP_PATH}"/squashfs-root/opt/conda/"${FULLENV}"

    ### Derived installation paths
    export CONDA_INSTALLATION_PATH=${CONDA_INSTALLATION_PATH:-${CONDA_BASE}/./${APPS_SUBDIR}/${CONDA_INSTALL_BASENAME}}

    echo "Copying base conda env"
    mkdir -p "${CONDA_OUTER_BASE}"
    rsync --recursive --links --perms --times --specials --partial --one-file-system --hard-links --acls --relative --exclude=*.sqsh -- "${CONDA_INSTALLATION_PATH}" "${CONDA_SCRIPT_PATH}" "${CONDA_MODULE_PATH}" "${CONDA_OUTER_BASE}"/

    echo "Copying external files"
    for f in "${outside_files_to_copy[@]}"; do
        mkdir -p "${OVERLAY_BASE}"/$( dirname "${f#/g/}" )
        cp "${f}" "${OVERLAY_BASE}"/"${f#/g/}"
    done

    echo "Unsquashing unstable environment"
    pushd "${CONDA_TEMP_PATH}"
    rm -rf squashfs-root
    unsquashfs -processors 1 "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}.sqsh"
    popd
    rm "${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/envs/"${FULLENV}"
    ln -sf "${ENV_INSTALLATION_PATH}" "${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/envs/

}

function launch() {
    "${SINGULARITY_BINARY_PATH}" -s exec --bind /etc,/half-root,/local,/ram,/run,/system,/usr,/var/lib/sss,/var/run/munge,/var/lib/rpm,"${OVERLAY_BASE}":/g "${CONTAINER_PATH}" bash
}

function finalise() {
    "${SINGULARITY_BINARY_PATH}" -s exec --bind /etc,/half-root,/local,/ram,/run,/system,/usr,/var/lib/sss,/var/run/munge,/var/lib/rpm,"${OVERLAY_BASE}":/g "${CONTAINER_PATH}" bash "${script_path}" --inner
    
    new_squashfs=$( mktemp -u "${PBS_JOBFS}"/"${FULLENV}".XXXXXX.sqsh )
    mksquashfs squashfs-root $new_squashfs -b 1M -no-recovery -noI -noD -noF -noX -processors 8 2>/dev/null
    echo "Updated squashfs created at "$new_squashfs
    pushd "${CONDA_OUTER_BASE}"
    tar --acls -cf "${PBS_JOBFS}"/conda_base.tar "${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}" "${MODULE_SUBDIR}" "${SCRIPT_SUBDIR}"
    echo "Base conda installation saved to ${PBS_JOBFS}/conda_base.tar"
    popd
}

_initialise

echo
echo "Ready. Run 'launch' to enter containerised environment"
echo "When you're done, exit the container and run 'finalise'"