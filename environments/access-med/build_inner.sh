### Custom install inner to build jupyter lab extensions

set +u
eval "$( ${MAMBA} shell hook --shell bash)"
micromamba activate "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}"
set -u

# Fix shebang in esmvaltool 
sed -i "1s|^#!/.*$|#!${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/bin/python|" ${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/bin/ilamb-run

jupyter lab build