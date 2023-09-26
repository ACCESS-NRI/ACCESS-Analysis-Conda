#!/usr/bin/env bash
set -eu

[[ "${SCRIPT_DIR}" ]] && cd "${SCRIPT_DIR}"

source install_config.sh
source functions.sh

### Derived temp file locations
export OVERLAY_BASE="${CONDA_TEMP_PATH}"/overlay/
export CONDA_OUTER_BASE="${OVERLAY_BASE}"/"${CONDA_BASE#/*/}"

### Derived installation path
export CONDA_INSTALLATION_PATH="${CONDA_INSTALLATION_PATH:-$CONDA_BASE/$APPS_SUBDIR/$CONDA_INSTALL_BASENAME}"

function inner() {

    mkdir -p "${CONDA_INSTALLATION_PATH%/*}"
    bash Miniconda3-py39_4.12.0-Linux-x86_64.sh -b -p "${CONDA_INSTALLATION_PATH}"

    . "${CONDA_INSTALLATION_PATH}"/etc/profile.d/conda.sh
    conda install mamba -y

    mkdir -p "${CONDA_SCRIPT_PATH}"/overrides
    cp "${SCRIPT_DIR}"/launcher.sh "${CONDA_SCRIPT_PATH}"
    cp "${SCRIPT_DIR}"/overrides/* "${CONDA_SCRIPT_PATH}"/overrides

    mkdir -p "${CONDA_MODULE_PATH}"
    ### These files contain hard-coded paths to the conda installation - these paths are created with variables set by install_config.sh
    copy_and_replace "${SCRIPT_DIR}"/../modules/common_v3 "${CONDA_MODULE_PATH}"/.common_v3       CONDA_BASE APPS_SUBDIR CONDA_INSTALL_BASENAME SCRIPT_SUBDIR
    copy_and_replace "${SCRIPT_DIR}"/launcher_conf.sh     "${CONDA_SCRIPT_PATH}"/launcher_conf.sh CONDA_BASE APPS_SUBDIR CONDA_INSTALL_BASENAME

    conda clean -a -f -y

}

if [[ $# -gt 0 ]]; then
    if [[ "${1}" == '--inner' ]]; then
        inner
        exit
    fi
fi

wget https://repo.anaconda.com/miniconda/Miniconda3-py39_4.12.0-Linux-x86_64.sh

mkdir -p "${OVERLAY_BASE}"
"${SINGULARITY_BINARY_PATH}" -s exec --bind /etc,/half-root,/local,/ram,/run,/system,/usr,/var/lib/sss,/var/run/munge,/var/lib/rpm,"${OVERLAY_BASE}":/g "${CONTAINER_PATH}" $( realpath $0 ) --inner

### Copy in container
cp "${CONTAINER_PATH}" "${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/etc/
### Set permissions
set_apps_perms "${CONDA_OUTER_BASE}"

#rsync --archive --verbose --partial --progress --one-file-system --hard-links --acls --relative -- "${CONDA_OUTER_BASE}"/./"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}" "${CONDA_OUTER_BASE}"/./"${SCRIPT_SUBDIR}" "${CONDA_OUTER_BASE}"/./"${MODULE_SUBDIR}" "${BUILD_STAGE_DIR}"

### To be made by jenkins
#mkdir -p "${ADMIN_DIR}"
#chgrp "${APPS_OWNERS_GROUP}" "${ADMIN_DIR}"
#chmod g=u+s,o= "${ADMIN_DIR}"


pushd "${CONDA_OUTER_BASE}"
### WARNING: Non-standard tar extension: --acls
tar --acls -cf "${BUILD_STAGE_DIR}"/conda_base.tar "${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}" "${SCRIPT_SUBDIR}" "${MODULE_SUBDIR}"
popd

rm -f Miniconda3-py39_4.12.0-Linux-x86_64.sh
