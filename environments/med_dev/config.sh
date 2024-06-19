### config.sh MUST provide the following:
### $FULLENV
###
### Arrays used by the build system (optional, can be empty)
### rpms_to_remove
### replace_from_apps
### outside_commands_to_include
### outside_files_to_copy


### Optional config for custom deploy script
export VERSION_TO_MODIFY=0.1
export STABLE_VERSION=0.1
export UNSTABLE_VERSION=0.2

### Version settings
export ENVIRONMENT=med_dev
export FULLENV="${ENVIRONMENT}-${VERSION_TO_MODIFY}"

declare -a rpms_to_remove=( "openssh-clients" "openssh-server" "openssh" )
declare -a replace_from_apps=( "openmpi/4.1.5" "ucx/1.14.0" )
declare -a outside_commands_to_include=( "pbs_tmrsh" "ssh" )
declare -a outside_files_to_copy=( "/g/data/hh5/public/apps/nci-intake-catalogue/catalogue_new.yaml" )
