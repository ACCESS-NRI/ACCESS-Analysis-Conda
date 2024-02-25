### Custom install inner to build jupyter lab extensions

set +u
eval "$( ${MAMBA} shell hook --shell bash)"
micromamba activate "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}"
set -u

jupyter lab build

pushd /opt/conda/esmvaltool-0.2/lib/python3.11/site-packages/esmvaltool
rm config-references.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config/config-references.yml config-references.yml
popd

pushd /opt/conda/esmvaltool-0.2/lib/python3.11/site-packages/esmvalcore
rm config-user.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config/config-user.yml config-user.yml
popd

pushd /opt/conda/esmvaltool-0.2/lib/python3.11/site-packages/esmvalcore
rm config-developer.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config/config-developer.yml config-developer.yml
popd