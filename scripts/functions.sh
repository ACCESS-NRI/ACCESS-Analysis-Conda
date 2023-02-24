### Useful functions
function in_array() {
    ### Assumes first n-1 args are an array and final arg is the string to search for
    ### Necessary because [[ libab =~ liba ]] returns true
    declare -a allargs=( "$@" )
    finalarg=${allargs[$(( ${#allargs[@]} - 1 ))]}
    for (( j=0; j<$(( ${#allargs[@]} - 1 )); j++ )); do
        [[ "${allargs[$j]}" == "${finalarg}" ]] && return 0
    done
    return 1
}

function get_aliased_module () {
    alias_name="${1}"
    module_path="${2}"
    while read al arrow mod; do 
        if [[ "${al}" == "${alias_name}" ]]; then
            echo "${mod}"
            return
        fi
    done < <( MODULEPATH="${module_path}" module aliases 2>&1 )
    echo ""
    return
}

function set_apps_perms() {

    for arg in "$@"; do
        if [[ -d "${arg}" ]]; then
            chgrp -R "${APPS_USERS_GROUP}" "${arg}"
            chmod -R g=u-w,o= "${arg}"
            chmod g+s "${arg}"
            setfacl -R -m g:"${APPS_OWNERS_GROUP}":rwX,d:g:"${APPS_OWNERS_GROUP}":rwX "${arg}"
        elif [[ -f "${arg}" ]]; then
            ### reset any existing acls
            setfacl -b "${arg}"
            chgrp "${APPS_USERS_GROUP}" "${arg}"
            chmod g=u-w,o= "${arg}"
            if [[ -x "${arg}" ]]; then
                setfacl -m g:"${APPS_OWNERS_GROUP}":rwX "${arg}"
            else
                setfacl -m g:"${APPS_OWNERS_GROUP}":rw "${arg}"
            fi
        elif [[ -h "${arg}" ]]; then
            chgrp -h "${APPS_USERS_GROUP}" "${arg}"
        fi
    done

}

function set_admin_perms() {

    for arg in "$@"; do
        if [[ -d "${arg}" ]]; then
            chgrp -R "${APPS_USERS_GROUP}" "${arg}"
            chmod -R g=u,o= "${arg}"
            chmod g+s "${arg}"
            setfacl -R -m g:"${APPS_USERS_GROUP}":---,g:"${APPS_OWNERS_GROUP}":rwX,d:g:"${APPS_USERS_GROUP}":---,d:g:"${APPS_OWNERS_GROUP}":rwX "${arg}"
        elif [[ -f "${arg}" ]]; then
            ### reset any existing acls
            setfacl -b "${arg}"
            chgrp "${APPS_USERS_GROUP}" "${arg}"
            chmod g=u,o= "${arg}"
            if [[ -x "${arg}" ]]; then
                setfacl -m g:"${APPS_USERS_GROUP}":---,g:"${APPS_OWNERS_GROUP}":rwX "${arg}"
            else
                setfacl -m g:"${APPS_USERS_GROUP}":---,g:"${APPS_OWNERS_GROUP}":rw "${arg}"
            fi
        elif [[ -h "${arg}" ]]; then
            chgrp -h "${APPS_USERS_GROUP}" "${arg}"
        fi
    done

}

function write_modulerc() {
    stable="${1}"
    unstable="${2}"
    env_name="${3}"
    module_path="${4}"
    module_name="${5}"

    cat<<EOF > "${module_path}"/"${module_name}"/.modulerc
#%Module1.0

module-version ${module_name}/${stable} analysis ${env_name} default
module-version ${module_name}/${unstable} ${env_name}-unstable

module-version ${module_name}/analysis27-18.10 analysis27
EOF

    set_apps_perms "${module_path}/${module_name}/.modulerc"

}

function symlink_atomic_update() {
    link_name="${1}"
    link_target="${2}"

    tmp_link_name=$( mktemp -u -p ${link_name%/*} .tmp.XXXXXXXX )

    ln -s "${link_target}" "${tmp_link_name}"
    mv -T "${tmp_link_name}" "${link_name}"

    set_apps_perms "${link_name}"
}

function construct_module_insert() {

    singularity_exec="${1}"
    overlay_path="${2}"
    container_path="${3}"
    squashfs_path="${4}"
    env_script="${5}"
    rootdir="${6}"
    condaenv="${7}"
    script_path="${8}"
    module_path="${9}"

    while read line; do
        key="${line%%=*}"
        value="${line#*=}"
        ### Skip these environment variables
        in_array "MODULEPATH" "_" "PWD" "SHLVL" "${key}" && continue
        ### Prepend to these variables
        if [[ $key =~ .PATH$ ]]; then
            echo prepend-path $key $value
        ### Prepend to Modulefile variables that work like a path
        elif in_array "_LMFILES_" "LOADEDMODULES" "${key}"; then
            echo prepend-path $key $value
        ### Treat path specially - remove system paths and retain order
        elif [[ "${key}" == "PATH" ]]; then
            while IFS= read -r -d: entry; do
                in_array "/bin" "/usr/bin" "${entry}" && continue
                if [[ $entry =~ $condaenv ]]; then
                    echo prepend-path PATH $script_path
                else
                    echo prepend-path PATH $entry
                fi
                echo prepend-path SINGULARITYENV_PREPEND_PATH $entry
            done<<<"${value%:}:"
        elif [[ "${key}" =~ ^alias\  ]]; then
            echo set-alias "${key//alias /}" "${value//\'/}"
        else
            if [[ "${value}" ]]; then
                echo setenv $key \"$value\"
            else
                echo setenv $key \"\"
            fi
        fi

    done < <( "${singularity_exec}" -s exec --bind /etc,/half-root,/local,/ram,/run,/system,/usr,/var/lib/sss,/var/run/munge,/var/lib/rpm,"${overlay_path}":/g --overlay="${squashfs_path}"  "${container_path}" /bin/env -i "${env_script}" "${rootdir}" "${condaenv}" ) > "${module_path}"

}

function copy_and_replace() {
    ### Copies the file in $1 to the location in $2 and replaces any occurence
    ### of __${3}__, __${4}__... with the contents of those environment variables
    in="${1}"
    out="${2}"
    shift 2
    sedstr=''
    for arg in "$@"; do
        sedstr="${sedstr}s:__${arg}__:${!arg}:g;"
    done
    
    if [[ "${sedstr}" ]]; then
        sed "${sedstr}" < "${in}" > "${out}"
    else
        cp "${in}" "${out}"
    fi

}