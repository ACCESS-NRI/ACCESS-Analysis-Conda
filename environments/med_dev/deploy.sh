### Update stable/unstable if necessary
CURRENT_STABLE=$( get_aliased_module "${MODULE_NAME}"/esmvaltool "${CONDA_MODULE_PATH}" )
NEXT_STABLE="${ENVIRONMENT}-${STABLE_VERSION}"
CURRENT_UNSTABLE=$( get_aliased_module "${MODULE_NAME}"/esmvaltool-unstable "${CONDA_MODULE_PATH}" )
NEXT_UNSTABLE="${ENVIRONMENT}-${UNSTABLE_VERSION}"

if ! [[ "${CURRENT_STABLE}" == "${MODULE_NAME}/${NEXT_STABLE}" ]]; then
    echo "Updating stable environment to ${NEXT_STABLE}"
    write_modulerc "${NEXT_STABLE}" "${NEXT_UNSTABLE}" "${ENVIRONMENT}" "${CONDA_MODULE_PATH}" "${MODULE_NAME}"
    symlink_atomic_update "${CONDA_INSTALLATION_PATH}"/envs/"${ENVIRONMENT}" "${NEXT_STABLE}"
    symlink_atomic_update "${CONDA_SCRIPT_PATH}"/"${ENVIRONMENT}".d "${NEXT_STABLE}".d
fi
if ! [[ "${CURRENT_UNSTABLE}" == "${MODULE_NAME}/${NEXT_UNSTABLE}" ]]; then
    echo "Updating unstable environment to ${NEXT_UNSTABLE}"
    write_modulerc "${NEXT_STABLE}" "${NEXT_UNSTABLE}" "${ENVIRONMENT}" "${CONDA_MODULE_PATH}" "${MODULE_NAME}"
    symlink_atomic_update "${CONDA_INSTALLATION_PATH}"/envs/"${ENVIRONMENT}"-unstable "${NEXT_UNSTABLE}"
    symlink_atomic_update "${CONDA_SCRIPT_PATH}"/"${ENVIRONMENT}"-unstable.d "${NEXT_UNSTABLE}".d
fi
