### Custom install inner to build jupyter lab extensions

set +u
eval "$( ${MAMBA} shell hook --shell bash)"
micromamba activate "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}"
set -u

# Fix shebang in esmvaltool 
sed -i "1s|^#!/.*$|#!${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/bin/python|" ${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/bin/esmvaltool
# Fix shebang in esgvoc 
sed -i "1s|^#!/.*$|#!${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/bin/python|" ${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/bin/esgvoc

jupyter lab build

PYTHON_VERSION=$(python -c "import sys; print(f'python{sys.version_info.major}.{sys.version_info.minor}')")

# User Tracking
pushd "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/lib/${PYTHON_VERSION}/site-packages"
ln -sf /g/data/xp65/admin/analysis3/sitecustomize.py sitecustomize.py
popd

# This is needed because NCI provides different versions of the mpi library depending on the required compiler
# but does not have a default. If we do not do this, the mpifh library will be linked against 
# the wrong mpi library and will not work properly.
pushd "${CONDA_INSTALLATION_PATH}/envs/${FULLENV}/lib/"
cp /apps/openmpi/5.0.8/lib/libmpi_mpifh_GNU.so.40.40.1 libmpi_mpifh.so.40.40.1
ln -sf libmpi_mpifh.so.40.40.1 libmpi_mpifh.so.40
ln -sf libmpi_mpifh.so.40.40.1 libmpi_mpifh.so
popd
