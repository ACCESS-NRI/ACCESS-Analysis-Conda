#!/usr/bin/env bash
if [[ ! "${CONDA_ENVIRONMENT}" ]]; then
    echo "Error! CONDA_ENVIRONMENT must be defined"
    exit 1
fi
set -eu

[[ "${SCRIPT_DIR}" ]] && cd "${SCRIPT_DIR}"

export CONDA_TEMP_PATH=$( mktemp -d -p "${BUILD_STAGE_DIR}" )
trap 'rm -rf "${CONDA_TEMP_PATH}"' EXIT

source install_config.sh
source functions.sh

export CONDA_INSTALLATION_PATH=${CONDA_INSTALLATION_PATH:-${CONDA_BASE}/./${APPS_SUBDIR}/${CONDA_INSTALL_BASENAME}}

### Do not package conda_base.tar or the updated env if there was no change
if diff -q "${BUILD_STAGE_DIR}"/deployed."${CONDA_ENVIRONMENT}".yml "${BUILD_STAGE_DIR}"/deployed."${CONDA_ENVIRONMENT}".old.yml; then
    echo "No changes detected in the environment, not deploying"
    rm -f "${BUILD_STAGE_DIR}"/deployed."${CONDA_ENVIRONMENT}".yml "${BUILD_STAGE_DIR}"/deployed."${CONDA_ENVIRONMENT}".old.yml
    exit
fi

mkdir -p "${CONDA_TEMP_PATH}"
pushd "${CONDA_TEMP_PATH}"
### WARNING: Non-standard tar extension: --acls
tar --acls -xf "${BUILD_STAGE_DIR}"/conda_base."${CONDA_ENVIRONMENT}".tar
popd

### A staged tar can predate a manual retirement. Publish only this version's
### entries; otherwise rsync (which intentionally has no global --delete) can
### restore module files and links for versions removed since the build.
for entry in "${CONDA_TEMP_PATH}/${APPS_SUBDIR}/${CONDA_INSTALL_BASENAME}/envs/"*; do
    [[ -e "${entry}" || -L "${entry}" ]] || continue
    [[ "${entry##*/}" == "${FULLENV}" ]] || rm -rf -- "${entry}"
done
for entry in "${CONDA_TEMP_PATH}/${MODULE_SUBDIR}/${MODULE_NAME}/"* "${CONDA_TEMP_PATH}/${MODULE_SUBDIR}/${MODULE_NAME}/".*; do
    [[ -e "${entry}" || -L "${entry}" ]] || continue
    case "${entry##*/}" in
        .|..|.common_v4|"${FULLENV}"|".${FULLENV}") ;;
        *) rm -rf -- "${entry}" ;;
    esac
done
for entry in "${CONDA_TEMP_PATH}/${SCRIPT_SUBDIR}/"*.d; do
    [[ -e "${entry}" || -L "${entry}" ]] || continue
    [[ "${entry##*/}" == "${FULLENV}.d" ]] || rm -rf -- "${entry}"
done


### rsync --archive attempts to set permissions on 
### "${CONDA_BASE}" itself, which results in errors.
set +e
echo "Sync across any changes in the base conda environment"
rsync --archive --verbose --partial --progress --one-file-system --itemize-changes --hard-links --acls --relative -- "${CONDA_TEMP_PATH}"/./"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}" "${CONDA_TEMP_PATH}"/./"${MODULE_SUBDIR}" "${CONDA_TEMP_PATH}"/./"${SCRIPT_SUBDIR}" "${CONDA_BASE}"
base_rsync_status=$?



echo "Make sure anything deleted from this environments scripts directory is also deleted from the prod copy"
rsync --archive --verbose --partial --progress --one-file-system --itemize-changes --hard-links --acls --relative --delete -- "${CONDA_TEMP_PATH}"/./"${SCRIPT_SUBDIR}"/"${FULLENV}".d "${CONDA_BASE}"
scripts_rsync_status=$?
if (( base_rsync_status != 0 || scripts_rsync_status != 0 )); then
    echo "Error: rsync failed; refusing to publish the image or retire versions" >&2
    exit 1
fi
set -e

[[ -e "${CONDA_INSTALLATION_PATH}"/envs/"${FULLENV}".sqsh ]] && cp "${CONDA_INSTALLATION_PATH}"/envs/"${FULLENV}".sqsh "${ADMIN_DIR}"/"${FULLENV}".sqsh.bak
mv "${BUILD_STAGE_DIR}"/"${FULLENV}".sqsh.tmp "${CONDA_INSTALLATION_PATH}"/envs/"${FULLENV}".sqsh

### Overwrite existing conda_base tarball
mv "${BUILD_STAGE_DIR}"/conda_base."${CONDA_ENVIRONMENT}".tar "${ADMIN_DIR}"
### Remove staging artefacts
rm -f "${BUILD_STAGE_DIR}"/deployed."${CONDA_ENVIRONMENT}".yml "${BUILD_STAGE_DIR}"/deployed."${CONDA_ENVIRONMENT}".old.yml "${BUILD_STAGE_DIR}"/"${FULLENV}".sqsh.tmp

if [[ -e "${SCRIPT_DIR}"/../environments/"${CONDA_ENVIRONMENT}"/deploy.sh ]]; then
    source "${SCRIPT_DIR}"/../environments/"${CONDA_ENVIRONMENT}"/deploy.sh
fi
