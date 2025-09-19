### Update stable/unstable if necessary
CURRENT_STABLE=$( get_aliased_module "${MODULE_NAME}"/analysis3 "${CONDA_MODULE_PATH}" )
NEXT_STABLE="${ENVIRONMENT}-${STABLE_VERSION}"
CURRENT_UNSTABLE=$( get_aliased_module "${MODULE_NAME}"/analysis3-unstable "${CONDA_MODULE_PATH}" )
NEXT_UNSTABLE="${ENVIRONMENT}-${UNSTABLE_VERSION}"

# Define the aliases for analysis3-edge
STABLE_ALIASES="analysis3-edge"
UNSTABLE_ALIASES="analysis3-edge-unstable"

# Check if this is a new unstable version being created for the first time
if [[ -z "${CURRENT_UNSTABLE}" ]] && [[ "${NEXT_UNSTABLE}" != "${NEXT_STABLE}" ]]; then
    echo "Creating new unstable version ${NEXT_UNSTABLE}, promoting ${NEXT_STABLE} to stable"
    write_modulerc "${NEXT_STABLE}" "${NEXT_UNSTABLE}" "${ENVIRONMENT}" "${CONDA_MODULE_PATH}" "${MODULE_NAME}" "${STABLE_ALIASES}" "${UNSTABLE_ALIASES}"
    symlink_atomic_update "${CONDA_INSTALLATION_PATH}"/envs/"${ENVIRONMENT}" "${NEXT_STABLE}"
    symlink_atomic_update "${CONDA_SCRIPT_PATH}"/"${ENVIRONMENT}".d "${NEXT_STABLE}".d
    symlink_atomic_update "${CONDA_INSTALLATION_PATH}"/envs/"${ENVIRONMENT}"-unstable "${NEXT_UNSTABLE}"
    symlink_atomic_update "${CONDA_SCRIPT_PATH}"/"${ENVIRONMENT}"-unstable.d "${NEXT_UNSTABLE}".d
else
    echo "Unstable version already exists or same as stable - no .modulerc changes needed"
    # Still update symlinks if versions changed
    if ! [[ "${CURRENT_STABLE}" == "${MODULE_NAME}/${NEXT_STABLE}" ]]; then
        echo "Updating stable symlinks to ${NEXT_STABLE}"
        symlink_atomic_update "${CONDA_INSTALLATION_PATH}"/envs/"${ENVIRONMENT}" "${NEXT_STABLE}"
        symlink_atomic_update "${CONDA_SCRIPT_PATH}"/"${ENVIRONMENT}".d "${NEXT_STABLE}".d
    fi
    if ! [[ "${CURRENT_UNSTABLE}" == "${MODULE_NAME}/${NEXT_UNSTABLE}" ]] && [[ "${NEXT_UNSTABLE}" != "${NEXT_STABLE}" ]]; then
        echo "Updating unstable symlinks to ${NEXT_UNSTABLE}"
        symlink_atomic_update "${CONDA_INSTALLATION_PATH}"/envs/"${ENVIRONMENT}"-unstable "${NEXT_UNSTABLE}"
        symlink_atomic_update "${CONDA_SCRIPT_PATH}"/"${ENVIRONMENT}"-unstable.d "${NEXT_UNSTABLE}".d
    fi
fi
