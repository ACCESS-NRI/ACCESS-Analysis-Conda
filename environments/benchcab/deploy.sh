CURRENT_ALIAS=$( get_aliased_module "${MODULE_NAME}/${ENVIRONMENT}" "${CONDA_MODULE_PATH}" )
NEXT_STABLE="${ENVIRONMENT}-${STABLE_VERSION}"

if ! [[ "${CURRENT_ALIAS}" == "${MODULE_NAME}/${NEXT_STABLE}" ]]; then
    # Update the current module alias to point to the next stable version:
    # usage: write_modulerc <next_stable> <next_unstable> <environment> <conda_module_path> <module_name> <stable_aliases> <unstable_aliases>
    write_modulerc "${NEXT_STABLE}" "" "${ENVIRONMENT}" "${CONDA_MODULE_PATH}" "${MODULE_NAME}" "${ENVIRONMENT}" ""
fi
