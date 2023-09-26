#!/usr/bin/env bash
### Not using set -eu in this script - we do not rely on the exit status
### to determine if the tests have failed. Success or otherwise of
### other commands in this script is immaterial

[[ "${SCRIPT_DIR}" ]] && cd "${SCRIPT_DIR}"

source install_config.sh
source functions.sh

### Derived temp file locations
export OVERLAY_BASE="${CONDA_TEMP_PATH}"/overlay
export CONDA_OUTER_BASE="${OVERLAY_BASE}"/"${CONDA_BASE#/*/}"
export CONDA_INSTALLATION_PATH=${CONDA_INSTALLATION_PATH:-${CONDA_BASE}/./${APPS_SUBDIR}/${CONDA_INSTALL_BASENAME}}

function inner() {

    source "${CONDA_INSTALLATION_PATH}"/etc/profile.d/conda.sh
    
    set +u
    conda activate "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}"
    set -u

    ### For reasons I can't figure out, py.test hangs on exit due to not being able to
    ### clean up one of its threads when run in singularity. To get around this, background
    ### py.test and read its status from an output file, rather than using the exit status
    rm -f "${TEST_OUT_FILE}"
    py.test -s --junitxml "${TEST_OUT_FILE}" &
    test_pid=$!

    while ! [[ -e "${TEST_OUT_FILE}" ]]; do sleep 5; done

    [[ -e /proc/"${test_pid}" ]] && kill -15 "${test_pid}"
    wait

}

if [[ "${1}" == '--inner' ]]; then
    inner "${2}"
    exit 0
fi

### Do not package conda_base.tar or the updated env if there was no change
if diff -q "${BUILD_STAGE_DIR}"/deployed.yml "${BUILD_STAGE_DIR}"/deployed.old.yml; then
    echo "No changes detected in the environment, not performing tests"
    exit
fi

mkdir -p "${CONDA_OUTER_BASE}"
pushd "${CONDA_OUTER_BASE}"
tar -xf "${BUILD_STAGE_DIR}"/conda_base.tar
popd

### Copy in any files outside the conda directory tree that may be needed
echo "Copying external files"
for f in "${outside_files_to_copy[@]}"; do
    mkdir -p "${OVERLAY_BASE}"/$( dirname "${f#/g/}" )
    cp "${f}" "${OVERLAY_BASE}"/"${f#/g/}"
done

if [[ -e "${CONTAINER_PATH}" ]]; then
    ### New container, use that
    my_container="${CONTAINER_PATH}"
else
    my_container="${CONDA_OUTER_BASE}"/"${APPS_SUBDIR}"/"${CONDA_INSTALL_BASENAME}"/etc/"${CONTAINER_PATH##*/}"
fi

"${SINGULARITY_BINARY_PATH}" -s exec --bind /etc,/half-root,/local,/ram,/run,/system,/usr,/var/lib/sss,/var/run/munge,/var/lib/rpm,"${OVERLAY_BASE}":/g --overlay="${BUILD_STAGE_DIR}"/"${FULLENV}".sqsh.tmp "${my_container}" $( realpath $0 ) --inner

if [[ ! -e "${TEST_OUT_FILE}" ]]; then
    echo "TESTS FILE MISSING - assuming tests have failed"
    exit 1
fi

read errors failures < <( python3 -c 'import xml.etree.ElementTree as ET; import sys; t=ET.parse(sys.argv[1]); print(t.getroot().getchildren()[0].get("errors") + " " + t.getroot().getchildren()[0].get("failures"))' "${TEST_OUT_FILE}" )

if [[ "${errors}" -gt 0 ]] || [[ "${failures}" -gt 0 ]]; then
    echo "TESTS FAILED - discarding update"
    exit 1
fi
