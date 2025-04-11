### Custom install inner to build jupyter lab extensions

set +u
eval "$( ${MAMBA} shell hook --shell bash)"
micromamba activate "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}"
set -u

# Fix shebang in esmvaltool 
sed -i "1s|^#!/.*$|#!${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/bin/python|" ${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/bin/esmvaltool

jupyter lab build

PYTHON_VERSION=$(python -c "import sys; print(f'python{sys.version_info.major}.{sys.version_info.minor}')")

pushd "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/lib/${PYTHON_VERSION}/site-packages/esmvaltool"
rm config-references.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config/config-references.yml config-references.yml
popd

pushd "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/lib/${PYTHON_VERSION}/site-packages/esmvalcore/config/configurations/defaults"
rm config-user.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config/config-user.yml config-user.yml
popd

pushd "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/lib/${PYTHON_VERSION}/site-packages/esmvalcore"
rm config-developer.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config/config-developer.yml config-developer.yml
popd
