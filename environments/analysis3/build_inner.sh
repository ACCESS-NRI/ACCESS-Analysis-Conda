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
ln -sf /g/data/xp65/public/apps/esmvaltool/config_2.0/config-references.yml config-references.yml
popd

pushd "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/lib/${PYTHON_VERSION}/site-packages/esmvalcore/config/configurations/defaults"
rm config-user.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config_2.0/config-user.yml config-user.yml
rm extra_facets_access.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config_2.0/extra_facets_access.yml extra_facets_access.yml
rm extra_facets_native6.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config_2.0/extra_facets_native6.yml extra_facets_native6.yml
popd

pushd "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/lib/${PYTHON_VERSION}/site-packages/esmvalcore/config/configurations"
rm data-esmvalcore-esgf.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config_2.0/data-esmvalcore-esgf.yml data-esmvalcore-esgf.yml
rm data-hpc-nci.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config_2.0/data-hpc-nci.yml data-hpc-nci.yml
rm data-native-access.yml
ln -sf /g/data/xp65/public/apps/esmvaltool/config_2.0/data-native-access.yml data-native-access.yml
popd

# User Tracking
pushd "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/lib/${PYTHON_VERSION}/site-packages"
cp /g/data/xp65/admin/analysis3/sitecustomize.py .
popd

# This is needed because NCI provides different versions of the mpi library depending on the required compiler
# but does not have a default. If we do not do this, the mpifh library will be linked against 
# the wrong mpi library and will not work properly.
pushd "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/lib/"
cp /apps/openmpi/5.0.8/lib/libmpi_mpifh_GNU.so.40.40.1 libmpi_mpifh.so.40.40.1
ln -sf libmpi_mpifh.so.40.40.1 libmpi_mpifh.so.40
ln -sf libmpi_mpifh.so.40.40.1 libmpi_mpifh.so
popd
