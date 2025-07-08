### config.sh MUST provide the following:
### $FULLENV
###
### Arrays used by the build system (optional, can be empty)
### rpms_to_remove
### replace_from_apps
### outside_commands_to_include
### outside_files_to_copy

### Optional config for custom deploy script
export VERSION_TO_MODIFY=25.06

### Version settings
export ENVIRONMENT=analysis3_edge
export FULLENV="${ENVIRONMENT}-${VERSION_TO_MODIFY}"

### CUDA version
export CONDA_OVERRIDE_CUDA=12

declare -a rpms_to_remove=( "openssh-clients" "openssh-server" "openssh" )
declare -a replace_from_apps=( "ucx/1.15.0" openmpi/5.9.5)
declare -a outside_commands_to_include=( "pbs_tmrsh" "ssh" )
#declare -a outside_files_to_copy=( "/g/data/xp65/public/apps/openmpi/4.1.6" )
#declare -a replace_with_external=( "/g/data/xp65/public/apps/openmpi/4.1.6" )
