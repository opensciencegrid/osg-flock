#!/usr/bin/env bash

# Auxiliary singularity wrapper script. Invoked by glidein_startup.sh when the script requires singularity
# singularity_wrapper VO_SCRIPT [script options and arguments - usually glidein_config, entry_id ]
# $1 - the script to run in Singularity
# $2 - glidien_config
# $3 - entry_id main, ...
#
# This script will also be invoked right after the download, no need to do test, ... here. No $3
# $1 - glidien_config
# $2 - entry_id main, ...

GWMS_THIS_SCRIPT="$0"
GWMS_THIS_SCRIPT_DIR=$(dirname "$0")
GWMS_VERSION_SINGULARITY_WRAPPER="sw20201013"

# Directory in Singularity where auxiliary files are copied (e.g. singularity_lib.sh)
GWMS_AUX_SUBDIR=${GWMS_AUX_SUBDIR:-".gwms_aux"}
# Directory where the base glidein directory is mounted, so test scripts have an environment similar to
# the user jobs but still access to the glidein directory through this directory (e.g. to glidien_config)
GWMS_BASE_SUBDIR=${GWMS_BASE_SUBDIR:-".gwms_base"}
# Directory to use for bin, lib, exec, ...
GWMS_SUBDIR=${GWMS_SUBDIR:-".gwms.d"}


# This should not need double invocation
# start, setup
# build singularity invocation
# we need re-invocation to do the setup internal in singularity (restore env var)
# invoke the script
# if singularity is not available? error or invoke w/o singularity?
# exec singularity?
# cleanup if needed


# TODO: should there be an option to disable output? Probably NO - like msg goes to glideins stdout/err
# To avoid GWMS debug and info messages in the job stdout/err (unless userjob option is set)
# [[ ! ",${GLIDEIN_DEBUG_OPTIONS}," = *,script,* ]] && GLIDEIN_QUIET=True


exit_wrapper () {
    # An error occurred. Communicate to glidein_startup.sh and then exit 1
    #  1: Error message
    #  2: Exit code (1 by default)
    #  may receive sleep time as 3, ignoring it
    #  4: Error type (default: Corruption) 
    #     https://glideinwms.fnal.gov/doc.prd/factory/validation_xml_output.html#error_types
    # The error is published to stderr, as default reported
    local exit_code=${2:-1}
    local error_type=${4:-Corruption}
    [[ -n "$1" ]] && warn_raw "ERROR: $error_type - $1"
    "$error_gen" -error "singularity_wrapper.sh" "$error_type" "$1" exit_code "$exit_code" script "$script_to_invoke"
    # Executing in the normal setup invocation chain. The following should be done normally
    #${main_dir}/error_augment.sh  -process $exit_code "${s_ffb_id}/script_wrapper.sh" "$PWD" "script_wrapper.sh $glidein_config" "$START" "$END"
    #${main_dir}/error_augment.sh -concat
    exit "$exit_code"
}

# In case singularity_lib cannot be imported
warn_raw() {
    echo "$@" 1>&2
}


################################################################################
#
# All code out here will run on the 1st invocation (whether Singularity is wanted or not)
# and also in the re-invocation within Singularity
# $HAS_SINGLARITY is used to discriminate if Singularity is desired (is 1) or not
# $GWMS_SINGULARITY_REEXEC is used to discriminate the re-execution (nothing outside, 1 inside)
#

script_to_invoke=$1
glidein_config=$2
entry_id=$3

if [[ -z "$3" ]]; then
    # initial invocation w/o script
    glidein_config=$1
fi

# Accessing glidein_config. This is the same file used by all other scripts 
# TODO: evaluate the use of a copy to control visibility/updates
if [[ ! -e "$glidein_config" ]]; then
    if [[ -e "$GWMS_THIS_SCRIPT_DIR/glidein_config" ]]; then
        glidein_config="$GWMS_THIS_SCRIPT_DIR/glidein_config"
    elif [[ -e "/srv/$GWMS_BASE_SUBDIR/glidein_config" ]]; then
        glidein_config="/srv/$GWMS_BASE_SUBDIR/glidein_config"
    fi
fi

# TODO: Should I quit if glidein_config is not available?

# error_gen defined also in singularity_lib.sh
[[ -e "$glidein_config" ]] && error_gen="$(grep '^ERROR_GEN_PATH ' "$glidein_config" | cut -d ' ' -f 2-)"

if [[ -z "$3" ]]; then
    # initial invocation w/o script
    "$error_gen" -ok "singularity_wrapper.sh"
    exit 0
fi

# Source utility files, outside and inside Singularity
# condor_job_wrapper is in the base directory, singularity_lib.sh in main
# and copied to RUNDIR/$GWMS_AUX_SUBDIR (RUNDIR becomes /srv in Singularity)
if [[ -e "$GWMS_THIS_SCRIPT_DIR/singularity_lib.sh" ]]; then
    GWMS_AUX_DIR="$GWMS_THIS_SCRIPT_DIR"
elif [[ -e /srv/$GWMS_AUX_SUBDIR/singularity_lib.sh ]]; then
    # In Singularity
    GWMS_AUX_DIR="/srv/$GWMS_AUX_SUBDIR"
elif [[ -e /srv/$GWMS_BASE_SUBDIR/main/singularity_lib.sh ]]; then
    # In Singularity w/ Glidein directory mounted
    GWMS_AUX_DIR="/srv/$GWMS_BASE_SUBDIR/main"
else
    warn_raw "ERROR: $GWMS_THIS_SCRIPT: Unable to source singularity_lib.sh! File not found. Quitting"
    exit_wrapper "Wrapper script $GWMS_THIS_SCRIPT failed: Unable to source singularity_lib.sh" 1
fi
# shellcheck source=./singularity_lib.sh
. "${GWMS_AUX_DIR}"/singularity_lib.sh

# Directory to use for bin, lib, exec, ... full path
# echo "DEBUG: checking for GWMS_DIR: env:$GWMS_DIR, `[[ -n "$GWMS_DIR" && -e "$GWMS_DIR/bin" ]] && echo OK`, $GWMS_THIS_SCRIPT_DIR/../$GWMS_SUBDIR/bin: `[[ -e $(dirname "$GWMS_THIS_SCRIPT_DIR")/$GWMS_SUBDIR/bin ]] && echo OK`, /srv/$GWMS_SUBDIR/bin : `[[ -e /srv/$GWMS_SUBDIR/bin ]] && echo OK`, /srv/$GWMS_BASE_SUBDIR/$GWMS_SUBDIR/bin: `[[ -e /srv/$GWMS_BASE_SUBDIR/$GWMS_SUBDIR/bin ]] && echo OK`, $GWMS_AUX_DIR/../$GWMS_SUBDIR/bin: `[[ -e /srv/$(dirname "$GWMS_AUX_DIR")/$GWMS_SUBDIR/bin ]] && echo OK`"
if [[ -n "$GWMS_DIR" && -e "$GWMS_DIR/bin" ]]; then
    # already set, keep it
    true
elif [[ -e $(dirname "$GWMS_THIS_SCRIPT_DIR")/$GWMS_SUBDIR/bin ]]; then
    GWMS_DIR=$(dirname "$GWMS_THIS_SCRIPT_DIR")/$GWMS_SUBDIR
elif [[ -e /srv/$GWMS_SUBDIR/bin ]]; then
    GWMS_DIR=/srv/$GWMS_SUBDIR
elif [[ -e /srv/$GWMS_BASE_SUBDIR/$GWMS_SUBDIR/bin ]]; then
    GWMS_DIR=/srv/$GWMS_BASE_SUBDIR/$GWMS_SUBDIR
elif [[ -e /srv/$(dirname "$GWMS_AUX_DIR")/$GWMS_SUBDIR/bin ]]; then
    GWMS_DIR=/srv/$(dirname "$GWMS_AUX_DIR")/$GWMS_SUBDIR/bin
else
    warn_raw "ERROR: $GWMS_THIS_SCRIPT: Unable to gind GWMS_DIR! File not found. Quitting"
    exit_wrapper "Wrapper script $GWMS_THIS_SCRIPT failed: Unable to find GWMS_DIR" 1
fi

# Calculating full version number, including md5 sums form the wrapper and singularity_lib
GWMS_VERSION_SINGULARITY_WRAPPER="${GWMS_VERSION_SINGULARITY_WRAPPER}_$(md5sum "$GWMS_THIS_SCRIPT" 2>/dev/null | cut -d ' ' -f1)_$(md5sum "${GWMS_AUX_DIR}/singularity_lib.sh" 2>/dev/null | cut -d ' ' -f1)"
info_dbg "GWMS singularity wrapper ($GWMS_VERSION_SINGULARITY_WRAPPER) starting, $(date). Imported singularity_lib.sh. glidein_config ($glidein_config)."
info_dbg "$GWMS_THIS_SCRIPT, in $(pwd), list: $(ls -al)"


# OSGVO - overrideing this from singularity_lib.sh
singularity_get_image() {
    # Return on stdout the Singularity image
    # Let caller decide what to do if there are problems
    # In:
    #  1: a comma separated list of platforms (OS) to choose the image
    #  2: a comma separated list of restrictions (default: none)
    #     - cvmfs: image must be on CVMFS
    #     - any: any image is OK, $1 was just a preference (the first one in SINGULARITY_IMAGES_DICT is used if none of the preferred is available)
    #  SINGULARITY_IMAGES_DICT
    #  SINGULARITY_IMAGE_DEFAULT (legacy)
    #  SINGULARITY_IMAGE_DEFAULT6 (legacy)
    #  SINGULARITY_IMAGE_DEFAULT7 (legacy)
    # Out:
    #  Singularity image path/URL returned on stdout
    #  EC: 0: OK, 1: Empty/no image for the desired OS (or for any), 2: File not existing, 3: restriction not met (e.g. image not on cvmfs)

    local s_platform="$1"
    if [[ -z "$s_platform" ]]; then
        warn "No desired platform, unable to select a Singularity image"
        return 1
    fi
    local s_restrictions="$2"
    local singularity_image

    # To support legacy variables SINGULARITY_IMAGE_DEFAULT, SINGULARITY_IMAGE_DEFAULT6, SINGULARITY_IMAGE_DEFAULT7
    # values are added to SINGULARITY_IMAGES_DICT
    # TODO: These override existing dict values OK for legacy support (in the future we'll add && [ dict_check_key rhel6 ] to avoid this)
    [[ -n "$SINGULARITY_IMAGE_DEFAULT6" ]] && SINGULARITY_IMAGES_DICT="`dict_set_val SINGULARITY_IMAGES_DICT rhel6 "$SINGULARITY_IMAGE_DEFAULT6"`"
    [[ -n "$SINGULARITY_IMAGE_DEFAULT7" ]] && SINGULARITY_IMAGES_DICT="`dict_set_val SINGULARITY_IMAGES_DICT rhel7 "$SINGULARITY_IMAGE_DEFAULT7"`"
    [[ -n "$SINGULARITY_IMAGE_DEFAULT" ]] && SINGULARITY_IMAGES_DICT="`dict_set_val SINGULARITY_IMAGES_DICT default "$SINGULARITY_IMAGE_DEFAULT"`"

    # [ -n "$s_platform" ] not needed, s_platform is never null here (verified above)
    # Try a match first, then check if there is "any" in the list
    singularity_image="`dict_get_val SINGULARITY_IMAGES_DICT "$s_platform"`"
    if [[ -z "$singularity_image" && ",${s_platform}," = *",any,"* ]]; then
        # any means that any image is OK, take the 'default' one and if not there the   first one
        singularity_image="`dict_get_val SINGULARITY_IMAGES_DICT default`"
        [[ -z "$singularity_image" ]] && singularity_image="`dict_get_first SINGULARITY_IMAGES_DICT`"
    fi

    # At this point, GWMS_SINGULARITY_IMAGE is still empty, something is wrong
    if [[ -z "$singularity_image" ]]; then
        [[ -z "$SINGULARITY_IMAGES_DICT" ]] && warn "No Singularity image available (SINGULARITY_IMAGES_DICT is empty)" ||
                warn "No Singularity image available for the required platforms ($s_platform)"
        return 1
    fi

    # Check all restrictions (at the moment cvmfs) and return 3 if failing
    #if [[ ",${s_restrictions}," = *",cvmfs,"* ]] && ! singularity_path_in_cvmfs "$singularity_image"; then
    #    warn "$singularity_image is not in /cvmfs area as requested"
    #    return 3
    #fi

    # We make sure it exists
    #if [[ ! -e "$singularity_image" ]]; then
    #    warn "ERROR: $singularity_image file not found" 1>&2
    #    return 2
    #fi

    # For now, let's test on ITB!
    if (echo "$singularity_image" | grep "^/cvmfs/singularity.opensciencegrid.org/") >/dev/null 2>&1; then
        singularity_image=$(echo "$singularity_image" | sed 's;^/cvmfs/singularity.opensciencegrid.org;docker://hub.opensciencegrid.org;')
    fi

    # Should we use CVMFS or pull images directly?
    # TODO - fix the test here
    if (echo "$singularity_image" | grep "^docker://") >/dev/null 2>&1; then
        # pull the image into a Singularity SIF file
        IMAGE_FNAME=$(echo "$singularity_image" | sed 's;docker://;;' | sed 's;[:/];__;g').sif
        singularity build $IMAGE_FNAME $singularity_image >$IMAGE_FNAME.log 2>&1
        if [ $? != 0 ]; then
            warn "Unable to download image ($singularity_image)"
            return 1
        fi
        singularity_image=$IMAGE_FNAME
    fi 

    echo "$singularity_image"
}


#################### main ###################

if [[ -z "$GWMS_SINGULARITY_REEXEC" ]]; then
    # Outside Singularity - Run this only on the 1st invocation
    info_dbg "GWMS singularity wrapper, first invocation"
    # Set up environment to know if Singularity is enabled and so we can execute Singularity
    # In the Glidein/setup: use the current environment or glidein_config, not the HTCondor ClassAd (condor not started yet)  
    setup_from_environment

    # Check if singularity is disabled or enabled
    # This script could run when singularity is optional and not wanted
    # So should not fail but exec w/o running Singularity

    if [[ "x$HAS_SINGULARITY" = "x1"  &&  "x$GWMS_SINGULARITY_PATH" != "x" ]]; then
        # Will run w/ Singularity - prepare for it
        info_dbg "GWMS singularity wrapper, decided to use singularity ($HAS_SINGULARITY, $GWMS_SINGULARITY_PATH). Proceeding w/ tests and setup."

        # OSGVO - disabled for now
        # If a repo CVMFS_REPOS_LIST is not available exit with 1
        #cvmfs_test_and_open "$CVMFS_REPOS_LIST" exit_wrapper
        
        # OSGVO: unset modules leftovers from the site environment 
        for KEY in \
              ENABLE_LMOD \
              _LMFILES_ \
              LOADEDMODULES \
              MODULEPATH \
              MODULEPATH_ROOT \
              MODULESHOME \
              $(env | sed 's/=.*//' | egrep "^LMOD" 2>/dev/null) \
              $(env | sed 's/=.*//' | egrep "^SLURM" 2>/dev/null) \
        ; do
            eval VAL="\$$KEY"
            if [ "x$VAL" != "x" ]; then
                info_dbg "Unsetting env var provided by site: $KEY"
            fi
            unset $KEY
        done

        # Re-invoke this script in singularity
        singularity_prepare_and_invoke "$@"
        # If we arrive here, then something failed in Singularity but is OK to continue w/o
    else
        # First execution, no Singularity.
        info_dbg "GWMS singularity wrapper, first invocation, not using singularity ($HAS_SINGULARITY, $GWMS_SINGULARITY_PATH)"
    fi

else
    # We are now inside Singularity

    # Need to start in /srv (Singularity's --pwd is not reliable)
    # /srv should always be there in Singularity, we set the option '--home \"$PWD\":/srv'
    [[ -d /srv ]] && cd /srv
    export HOME=/srv

    # Changing env variables (especially TMP and X509 related) to work w/ chrooted FS
    singularity_setup_inside
    info_dbg "GWMS singularity wrapper, running inside singularity env = $(printenv)"

fi

################################################################################
#
# Setup for job execution
# This section will be executed:
# - in Singularity (if $GWMS_SINGULARITY_REEXEC not empty)
# - if is OK to run w/o Singularity ( $HAS_SINGULARITY" not true OR $GWMS_SINGULARITY_PATH" empty )
# - if setup or exec of singularity failed (and it is possible to fall-back to no Singularity)
#
info_dbg "GWMS singularity wrapper, final setup."

gwms_process_scripts "$GWMS_DIR" prejob

# TODO: is the cleanup needed? It is OK for the scripts to access/modify the glidein environment
# $GWMS_AUX_SUBDIR, $GWMS_BASE_SUBDIR mount point
# Aux dir in the future mounted read only. Remove the directory if in Singularity
# TODO: should always auxdir be copied and removed? Should be left for the job?

#  Run the real test script
info_dbg "current directory at execution ($(pwd)): $(ls -al)"
info_dbg "GWMS singularity wrapper, job exec: \"$script_to_invoke\" \"$glidein_config\" \"$entry_id\""
info_dbg "GWMS singularity wrapper, messages after this line are from the actual script ##################"
exec "$script_to_invoke" "$glidein_config" "$entry_id"
error=$?
# exec failed. Something is wrong w/ the worker node
exit_wrapper "exec failed  (Singularity:$GWMS_SINGULARITY_REEXEC, exit code:$error): $*" $error "" WN_Resource
