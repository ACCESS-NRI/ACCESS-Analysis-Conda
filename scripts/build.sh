#!/usr/bin/env bash
set -eu

[[ "${SCRIPT_DIR}" ]] && cd "${SCRIPT_DIR}"

source install_config.sh
source functions.sh

### Derived temp file locations
export OVERLAY_BASE="${CONDA_TEMP_PATH}"/overlay
export CONDA_OUTER_BASE="${OVERLAY_BASE}"/"${CONDA_BASE#/*/}"
export ENV_INSTALLATION_PATH="${CONDA_TEMP_PATH}"/squashfs-root/opt/conda/"${FULLENV}"

### Derived installation paths
export CONDA_INSTALLATION_PATH=${CONDA_INSTALLATION_PATH:-${CONDA_BASE}/./${APPS_SUBDIR}/${CONDA_INSTALL_BASENAME}}
export MAMBA="${CONDA_INSTALLATION_PATH}"/condabin/mamba

function inner() {

    source "${CONDA_INSTALLATION_PATH}"/etc/profile.d/conda.sh
    ### Create the environment
    if [[ "${1}" == "--install" ]]; then
        ${MAMBA} env create -p "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}" -f environment.yml
        if [[ $? -ne 0 ]]; then
            echo "Error installing new environment"
            exit 1
        fi
    elif [[ "${1}" == "--update" ]]; then
        cat "${CONDA_INSTALLATION_PATH}"/envs/${FULLENV}/conda-meta/history >> "${CONDA_INSTALLATION_PATH}"/envs/${FULLENV}/conda-meta/history.log
        echo > "${CONDA_INSTALLATION_PATH}"/envs/${FULLENV}/conda-meta/history
        conda env export -p "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}" > deployed.old.yml
        ${MAMBA} env update -p "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}" -f environment.yml
        if [[ $? -ne 0 ]]; then
            echo "Error updating new environment"
            exit 1
        fi

        ### Destroy the existing symlink tree
        rm -rf "${CONDA_SCRIPT_PATH}"/"${FULLENV}".d/{bin,overrides}
    fi
    
    conda env export -p "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}" > deployed.yml

    if [[ "${1}" == "--update" ]] && diff -q deployed.yml deployed.old.yml; then
        echo "No changes detected in the environment, discarding update"
        exit 0
    fi

    pushd "${ENV_INSTALLATION_PATH}"
    ### Get rid of stuff from packages we don't want
    for dir in bin lib etc libexec include; do 
        pushd $dir
        for i in $( rpm -qli "${rpms_to_remove[@]}" ); do 
            fn=$( basename $i )
            [[ -f $fn ]] && rm $fn
            [[ -d $fn ]] && rm -rf $fn
        done
        popd
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

    set +u
    conda activate "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}"
    set -u

    jupyter lab build
    # esmvaltool install Julia
    conda clean -a -f -y
    conda list

}

if [[ "$#" -gt 1 ]]; then
    if [[ "${1}" == '--inner' ]]; then
        inner "${2}"
        exit 0
    fi
fi

if [[ -d "${CONDA_INSTALLATION_PATH}" ]]; then
    mkdir -p "${CONDA_OUTER_BASE}"
    echo "Copying base conda installation to ${CONDA_TEMP_PATH}"
    rsync --recursive --links --perms --times --specials --partial --one-file-system --hard-links --acls --relative --exclude=*.sqsh -- "${CONDA_INSTALLATION_PATH}" "${CONDA_SCRIPT_PATH}" "${CONDA_MODULE_PATH}" "${CONDA_OUTER_BASE}"/
    echo "Done"
else
    echo "Base installation not present - initialising"
    ./initialise.sh
fi

### Copy in any files outside the conda directory tree that may be needed
echo "Copying external files"
for f in "${outside_files_to_copy[@]}"; do
    mkdir -p "${OVERLAY_BASE}"/$( dirname "${f#/g/}" )
    cp "${f}" "${OVERLAY_BASE}"/"${f#/g/}"
done

if [[ -e  "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}.sqsh" ]]; then
    pushd "${CONDA_TEMP_PATH}"
    unsquashfs -processors 1 "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}.sqsh"
    popd
    rm "${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/envs/"${FULLENV}"
    export DO_UPDATE="--update"
else
    mkdir -p "${ENV_INSTALLATION_PATH}"
    export DO_UPDATE="--install"
fi

ln -sf "${ENV_INSTALLATION_PATH}" "${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/envs/

if [[ -e "${CONTAINER_PATH}" ]]; then
    ### New container, use that
    my_container="${CONTAINER_PATH}"
else
    my_container="${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/etc/"${CONTAINER_PATH##*/}"
fi

"${SINGULARITY_BINARY_PATH}" -s exec --bind /etc,/half-root,/local,/ram,/run,/system,/usr,/var/lib/sss,/var/run/munge,/var/lib/rpm,"${OVERLAY_BASE}":/g "${my_container}" $( realpath $0 ) --inner "${DO_UPDATE}"
if [[ $? -ne 0 ]]; then
    exit 1
fi

### See if the container has been updated
### The container will only exist on ${CONTAINER_PATH} if it was built by the github action
#read newhash fn < <( md5sum "${CONTAINER_PATH}" )
#read oldhash fn < <( md5sum "${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/etc/"${CONTAINER_PATH##*/}" )
if [[ -e "${CONTAINER_PATH}" ]]; then
    echo "Container update detected. Copying in new container"
    cp "${CONTAINER_PATH}" "${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/etc/"${CONTAINER_PATH##*/}"
fi

if [[ "${DO_UPDATE}" == "--update" ]] && diff -q deployed.yml deployed.old.yml; then
    echo "No changes detected in the environment, discarding update"
    cp deployed.yml deployed.old.yml "${BUILD_STAGE_DIR}"/
    exit 0
fi


if [[ "${DO_UPDATE}" == "--install" ]]; then
    ln -s .common_v3 "${CONDA_OUTER_BASE}"/"${MODULE_SUBDIR}"/"${MODULE_NAME}"/"${FULLENV}"
fi

pushd "${CONDA_TEMP_PATH}"
### Set permissions
### Don't need to think too hard, squashfs are read-only
chgrp -R "${APPS_USERS_GROUP}" squashfs-root

mksquashfs squashfs-root "${FULLENV}".sqsh -no-fragments -no-duplicates -no-sparse -no-exports -no-recovery -noI -noD -noF -noX -processors 8 2>/dev/null
### Stage this file and rename when we're ready
cp "${FULLENV}".sqsh "${BUILD_STAGE_DIR}"/"${FULLENV}".sqsh.tmp
set_apps_perms "${BUILD_STAGE_DIR}"/"${FULLENV}".sqsh.tmp
popd

### Can't use ${CONDA_SCRIPT_PATH} or "${CONDA_INSTALLATION_PATH}" due to the need to string match on those paths
### which they won't with the '/./' part required for arcane rsync magic
construct_module_insert "${SINGULARITY_BINARY_PATH}" "${OVERLAY_BASE}" "${my_container}" "${BUILD_STAGE_DIR}"/"${FULLENV}".sqsh.tmp "${SCRIPT_DIR}"/condaenv.sh "${CONDA_INSTALLATION_PATH}" "${CONDA_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/envs/"${FULLENV}" "${CONDA_BASE}"/"${SCRIPT_SUBDIR}"/"${FULLENV}".d/bin "${CONDA_OUTER_BASE}"/"${MODULE_SUBDIR}"/"${MODULE_NAME}"/."${FULLENV}"

rm "${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/envs/"${FULLENV}"
ln -s /opt/conda/"${FULLENV}" "${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/envs/

### Set permissions on base environment
set_apps_perms "${CONDA_OUTER_BASE}"

### Archive base env
pushd "${CONDA_OUTER_BASE}"
### WARNING: Non-standard tar extension: --acls
tar --acls -cf "${BUILD_STAGE_DIR}"/conda_base.tar "${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}" "${MODULE_SUBDIR}" "${SCRIPT_SUBDIR}"
popd

cp deployed.yml "${BUILD_STAGE_DIR}"/
### || true so the script doesn't report failed if its doing a fresh install.
[[ "${DO_UPDATE}" == "--update" ]] && cp deployed.old.yml "${BUILD_STAGE_DIR}"/ || true
