#!/bin/bash
# GlideinWMS singularity wrapper. Invoked by HTCondor as user_job_wrapper
# default_singularity_wrapper USER_JOB [job options and arguments]
EXITSLEEP=10m
GWMS_THIS_SCRIPT="$0"
GWMS_THIS_SCRIPT_DIR=$(dirname "$0")

# Directory in Singularity where auxiliary files are copied (e.g. singularity_lib.sh)
GWMS_AUX_SUBDIR=${GWMS_AUX_SUBDIR:-".gwms_aux"}
export GWMS_AUX_SUBDIR
# GWMS_BASE_SUBDIR (directory where the base glidein directory is mounted) not defiled in Singularity for the user jobs, only for setup scripts
# Directory to use for bin, lib, exec, ...
GWMS_SUBDIR=${GWMS_SUBDIR:-".gwms.d"}
export GWMS_SUBDIR

# CVMFS_BASE defaults to /cvmfs but can be overridden in case of for example cvmfsexec
if [ "x$CVMFS_BASE" = "x" ]; then
    CVMFS_BASE="/cvmfs"
fi

GWMS_VERSION_SINGULARITY_WRAPPER=20201013
# Updated using OSG wrapper #5d8b3fa9b258ea0e6640727405f20829d2c5d4b9
# https://github.com/opensciencegrid/osg-flock/blob/master/job-wrappers/user-job-wrapper.sh
# Link to the CMS wrapper
# https://gitlab.cern.ch/CMSSI/CMSglideinWMSValidation/-/blob/master/singularity_wrapper.sh

################################################################################
#
# All code out here will run on the 1st invocation (whether Singularity is wanted or not)
# and also in the re-invocation within Singularity
# $HAS_SINGLARITY is used to discriminate if Singularity is desired (is 1) or not
# $GWMS_SINGULARITY_REEXEC is used to discriminate the re-execution (nothing outside, 1 inside)
#

# To avoid GWMS debug and info messages in the job stdout/err (unless userjob option is set)
[[ ! ",${GLIDEIN_DEBUG_OPTIONS}," = *,userjob,* ]] && GLIDEIN_QUIET=True
[[ ! ",${GLIDEIN_DEBUG_OPTIONS}," = *,nowait,* ]] && EXITSLEEP=2m  # leave 2min to update classad

# When failing we need to tell HTCondor to put the job back in the queue by creating
# a file in the PATH pointed by $_CONDOR_WRAPPER_ERROR_FILE
# Make sure there is no leftover wrapper error file (if the file exists HTCondor assumes the wrapper failed)
[[ -n "$_CONDOR_WRAPPER_ERROR_FILE" ]] && rm -f "$_CONDOR_WRAPPER_ERROR_FILE" >/dev/null 2>&1 || true


exit_wrapper () {
    # An error occurred. Communicate to HTCondor and avoid black hole (sleep for hold time) and then exit 1
    #  1: Error message
    #  2: Exit code (1 by default)
    #  3: sleep time (default: $EXITSLEEP)
    # The error is published to stderr, if available to $_CONDOR_WRAPPER_ERROR_FILE,
    # if chirp available sets JobWrapperFailure
    [[ -n "$1" ]] && warn_raw "ERROR: $1"
    local exit_code=${2:-1}
    local sleep_time=${3:-$EXITSLEEP}
    local publish_fail
    # Publish the error so that HTCondor understands that is a wrapper error and retries the job
    if [[ -n "$_CONDOR_WRAPPER_ERROR_FILE" ]]; then
        warn "Wrapper script failed, creating condor log file: $_CONDOR_WRAPPER_ERROR_FILE"
        echo "Wrapper script $GWMS_THIS_SCRIPT failed ($exit_code): $1" >> $_CONDOR_WRAPPER_ERROR_FILE
    else
        publish_fail="HTCondor error file"
    fi
    # also chirp
    if [[ -e ../../main/condor/libexec/condor_chirp ]]; then
        ../../main/condor/libexec/condor_chirp set_job_attr JobWrapperFailure "Wrapper script $GWMS_THIS_SCRIPT failed ($exit_code): $1"
    else
        [[ -n "$publish_fail" ]] && publish_fail="${publish_fail} and "
        publish_fail="${publish_fail}condor_chirp"
    fi

    # TODO: also this?: touch ../../.stop-glidein.stamp >/dev/null 2>&1

    [[ -n "$publish_fail" ]] && warn "Failed to communicate ERROR with ${publish_fail}"

    #  TODO: Add termination stamp? see OSG
    #              touch ../../.stop-glidein.stamp >/dev/null 2>&1
    # Eventually the periodic validation of singularity will make the pilot
    # to stop matching new payloads
    # Prevent a black hole by sleeping EXITSLEEP (10) minutes before exiting. Sleep time can be changed on top of this file
    sleep $sleep_time
    exit $exit_code
}

# In case singularity_lib cannot be imported
warn_raw () {
    echo "$@" 1>&2
}

# Ensure all jobs have PATH set
# bash can set a default PATH - make sure it is exported
export PATH=$PATH
[[ -z "$PATH" ]] && export PATH="/usr/local/bin:/usr/bin:/bin"

[[ -z "$glidein_config" ]] && [[ -e "$GWMS_THIS_SCRIPT_DIR/glidein_config" ]] &&
    glidein_config="$GWMS_THIS_SCRIPT_DIR/glidein_config"

# error_gen defined also in singularity_lib.sh
[[ -e "$glidein_config" ]] && error_gen="$(grep '^ERROR_GEN_PATH ' "$glidein_config" | cut -d ' ' -f 2-)"


# Source utility files, outside and inside Singularity
# condor_job_wrapper is in the base directory, singularity_lib.sh in main
# and copied to RUNDIR/$GWMS_AUX_SUBDIR (RUNDIR becomes /srv in Singularity)
if [[ -e "$GWMS_THIS_SCRIPT_DIR/main/singularity_lib.sh" ]]; then
    GWMS_AUX_DIR="$GWMS_THIS_SCRIPT_DIR/main"
elif [[ -e /srv/$GWMS_AUX_SUBDIR/singularity_lib.sh ]]; then
    # In Singularity
    GWMS_AUX_DIR="/srv/$GWMS_AUX_SUBDIR"
else
    echo "ERROR: $GWMS_THIS_SCRIPT: Unable to source singularity_lib.sh! File not found. Quitting" 1>&2
    warn=warn_raw
    exit_wrapper "Wrapper script $GWMS_THIS_SCRIPT failed: Unable to source singularity_lib.sh" 1
fi
# shellcheck source=../singularity_lib.sh
. "${GWMS_AUX_DIR}"/singularity_lib.sh

# Directory to use for bin, lib, exec, ... full path
if [[ -n "$GWMS_DIR" && -e "$GWMS_DIR/bin" ]]; then
    # already set, keep it
    true
elif [[ -e $GWMS_THIS_SCRIPT_DIR/$GWMS_SUBDIR/bin ]]; then
    GWMS_DIR=$GWMS_THIS_SCRIPT_DIR/$GWMS_SUBDIR
elif [[ -e /srv/$GWMS_SUBDIR/bin ]]; then
    GWMS_DIR=/srv/$GWMS_SUBDIR
elif [[ -e /srv/$(dirname "$GWMS_AUX_DIR")/$GWMS_SUBDIR/bin ]]; then
    GWMS_DIR=/srv/$(dirname "$GWMS_AUX_DIR")/$GWMS_SUBDIR/bin
else
    echo "ERROR: $GWMS_THIS_SCRIPT: Unable to gind GWMS_DIR! File not found. Quitting" 1>&2
    exit_wrapper "Wrapper script $GWMS_THIS_SCRIPT failed: Unable to find GWMS_DIR" 1
fi
export GWMS_DIR

# Calculating full version number, including md5 sums form the wrapper and singularity_lib
GWMS_VERSION_SINGULARITY_WRAPPER="${GWMS_VERSION_SINGULARITY_WRAPPER}_$(md5sum "$GWMS_THIS_SCRIPT" 2>/dev/null | cut -d ' ' -f1)_$(md5sum "${GWMS_AUX_DIR}/singularity_lib.sh" 2>/dev/null | cut -d ' ' -f1)"
info_dbg "GWMS singularity wrapper ($GWMS_VERSION_SINGULARITY_WRAPPER) starting, $(date). Imported singularity_lib.sh. glidein_config ($glidein_config)."
info_dbg "$GWMS_THIS_SCRIPT, in $(pwd), list: $(ls -al)"

# Should we use CVMFS or pull images directly?
ALLOW_NONCVMFS_IMAGES=$(get_prop_bool "$_CONDOR_MACHINE_AD" "ALLOW_NONCVMFS_IMAGES" 0)
info_dbg "ALLOW_NONCVMFS_IMAGES: $ALLOW_NONCVMFS_IMAGES"

download_singularity_image () {
    local singularity_image="$1"
    # TODO - fix the test here
    #        base it on ALLOW_NONCVMFS_IMAGES
    set -x
    if (echo "$singularity_image" | grep "^docker://") >/dev/null 2>&1; then
        # pull the image into a Singularity SIF file
        IMAGE_FNAME=$(echo "$singularity_image" | sed 's;docker://;;' | sed 's;[:/];__;g').sif
        if [ ! -e ../../$IMAGE_FNAME ]; then
            (curl -L -s -S -f -o ../../$IMAGE_FNAME.$$ https://data.isi.edu/osg/images/$IMAGE_FNAME \
                || wget -nv --timeout=300 --tries=1 -O ../../$IMAGE_FNAME.$$ https://data.isi.edu/osg/images/$IMAGE_FNAME \
                || $GWMS_SINGULARITY_PATH build --force ../../$IMAGE_FNAME.$$ $singularity_image) >../../$IMAGE_FNAME.log 2>&1
            if [ $? != 0 ]; then
                warn "Unable to download image ($singularity_image)"
                if [[ -s $IMAGE_FNAME.log ]]; then
                    warn "Dumping $IMAGE_FNAME.log:"
                    cat $IMAGE_FNAME.log >&2
                fi
                set +x
                return 1
            fi
            mv ../../$IMAGE_FNAME.$$ ../../$IMAGE_FNAME
        fi
        singularity_image=$PWD/../../$IMAGE_FNAME
    fi
    echo "$singularity_image"
    set +x
    return 0
}



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

    # TODO Reenable this based on ALLOW_NONCVMFS_IMAGES
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
    # Translate /cvmfs image name to hub.opensciencegrid.org image
    if (echo "$singularity_image" | grep "^/cvmfs/singularity.opensciencegrid.org/") >/dev/null 2>&1; then
        singularity_image=$(echo "$singularity_image" | sed 's;^/cvmfs/singularity.opensciencegrid.org;docker://hub.opensciencegrid.org;')
    fi

    singularity_image=$(download_singularity_image "$singularity_image") || return 1
    info_dbg "bind-path default (cvmfs:$GWMS_SINGULARITY_BIND_CVMFS, hostlib:$([ -n "$HOST_LIBS" ] && echo 1), ocl:$([ -e /etc/OpenCL/vendors ] && echo 1)): $GWMS_SINGULARITY_WRAPPER_BINDPATHS_DEFAULTS"

    echo "$singularity_image"
}


#################### main ###################

if [[ -z "$GWMS_SINGULARITY_REEXEC" ]]; then

    ################################################################################
    #
    # Outside Singularity - Run this only on the 1st invocation
    #

    info_dbg "GWMS singularity wrapper, first invocation"

    # Set up environment to know if Singularity is enabled and so we can execute Singularity
    setup_classad_variables

    # Check if singularity is disabled or enabled
    # This script could run when singularity is optional and not wanted
    # So should not fail but exec w/o running Singularity

    if [[ "x$HAS_SINGULARITY" = "x1"  &&  "x$GWMS_SINGULARITY_PATH" != "x" ]]; then
        #############################################################################
        #
        # Will run w/ Singularity - prepare for it
        # From here on the script assumes it has to run w/ Singularity
        #
        info_dbg "Decided to use singularity ($HAS_SINGULARITY, $GWMS_SINGULARITY_PATH). Proceeding w/ tests and setup."

        # OSGVO - disabled for now
        # We make sure that every cvmfs repository that users specify in CVMFSReposList is available, otherwise this script exits with 1
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

        GWMS_SINGULARITY_IMAGE=$(download_singularity_image "$GWMS_SINGULARITY_IMAGE") || exit 1

        singularity_prepare_and_invoke "${@}"

        # If we arrive here, then something failed in Singularity but is OK to continue w/o

    else  #if [ "x$HAS_SINGULARITY" = "x1" -a "xSINGULARITY_PATH" != "x" ];
        # First execution, no Singularity.
        info_dbg "GWMS singularity wrapper, first invocation, not using singularity ($HAS_SINGULARITY, $GWMS_SINGULARITY_PATH)"
    fi

else
    ################################################################################
    #
    # $GWMS_SINGULARITY_REEXEC not empty
    # We are now inside Singularity
    #

    # Need to start in /srv (Singularity's --pwd is not reliable)
    # /srv should always be there in Singularity, we set the option '--home \"$PWD\":/srv'
    # TODO: double check robustness, we allow users to override --home
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


# TODO: CodeRM1 to remove once gwms_process_scripts from singularity_lib.sh and the new setup_prejob.sh 
#  are in all the factories and frontends
if [[ "$(type -t gwms_process_scripts)" == 'function' ]]; then
    gwms_process_scripts "$GWMS_DIR" prejob
else
    #############################
    #
    #  modules and env
    #
    
    # TODO: to remove for sure once 'pychirp' is tried and tested
    # TODO: not needed here? It is in singularity_setup_inside for when Singularity is invoked, and should be already in the PATH when it is not
    # Checked - glidin_startup seems not to add condor to the path
    # Add Glidein provided HTCondor back to the environment (so that we can call chirp) - same is in
    # TODO: what if original and Singularity OS are incompatible? Should check and avoid adding condor back?
    if ! command -v condor_chirp > /dev/null 2>&1; then
        # condor_chirp not found, setting up form the condor library
        if [[ -e ../../main/condor/libexec ]]; then
            DER=$( (cd ../../main/condor; pwd) )
            export PATH="$DER/libexec:$PATH"
            # TODO: Check if LD_LIBRARY_PATH is needed or OK because of RUNPATH
            # export LD_LIBRARY_PATH="$DER/lib:$LD_LIBRARY_PATH"
        fi
    fi
    
    # fix discrepancy for Squid proxy URLs
    if [[ "x$GLIDEIN_Proxy_URL" = "x"  ||  "$GLIDEIN_Proxy_URL" = "None" ]]; then
        if [[ "x$OSG_SQUID_LOCATION" != "x"  &&  "$OSG_SQUID_LOCATION" != "None" ]]; then
            export GLIDEIN_Proxy_URL="$OSG_SQUID_LOCATION"
        fi
    fi
    
    # load modules and spack, if available
    # InitializeModulesEnv and MODULE_USE are 2 variables to enable the use of modules
    [[ "x$InitializeModulesEnv" = "x1" ]] && MODULE_USE=1
    
    if [[ "x$MODULE_USE" = "x1" ]]; then
        # Removed LMOD_BETA (/cvmfs/oasis.opensciencegrid.org/osg/sw/module-beta-init.sh), obsolete
        if [[ -e $CVMFS_BASE/oasis.opensciencegrid.org/osg/sw/module-init.sh  &&  -e $CVMFS_BASE/connect.opensciencegrid.org/modules/spack/share/spack/setup-env.sh ]]; then
            . $CVMFS_BASE/oasis.opensciencegrid.org/osg/sw/module-init.sh
        fi
        module -v >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            # module setup did not work, ignore it for the rest of the script
            MODULE_USE=0
        fi
    fi
    
    
    #############################
    #
    #  Stash cache
    #
    
    setup_stashcp () {
        if [[ "x$MODULE_USE" != "x1" ]]; then
            warn "Module unavailable. Unable to setup Stash cache if not in the environment."
            return 1
        fi
    
        # if we do not have stashcp in the path, load stashcache and xrootd from modules
        if ! which stashcp >/dev/null 2>&1; then
            module load stashcache >/dev/null 2>&1 || module load stashcp >/dev/null 2>&1
    
            # The OSG wrapper (as of 5d8b3fa9b258ea0e6640727405f20829d2c5d4b9) removed this xrdcp setup
            # We need xrootd, which is available both in the OSG software stack
            # as well as modules - use the system one by default
            if ! which xrdcp >/dev/null 2>&1; then
                module load xrootd >/dev/null 2>&1
            fi
    
            # Determine XRootD plugin directory.
            # in lieu of a MODULE_<name>_BASE from lmod, this will do:
            if [ -n "$XRD_PLUGINCONFDIR" ]; then
                MODULE_XROOTD_BASE=$(which xrdcp | sed -e 's,/bin/.*,,')
                export MODULE_XROOTD_BASE
                export XRD_PLUGINCONFDIR="$MODULE_XROOTD_BASE/etc/xrootd/client.plugins.d"
            fi
        fi
    
    }
    
    # Check for PosixStashCache first
    if [[ "x$POSIXSTASHCACHE" = "x1" ]]; then
        setup_stashcp
        if [[ $? -eq 0 ]]; then
    
            # Add the LD_PRELOAD hook
            export LD_PRELOAD="$MODULE_XROOTD_BASE/lib64/libXrdPosixPreload.so:$LD_PRELOAD"
    
            # Set proxy for virtual mount point
            # Format: cache.domain.edu/local_mount_point=/storage_path
            # E.g.: export XROOTD_VMP=data.ci-connect.net:/stash=/
            # Currently this points _ONLY_ to the OSG Connect source server
            export XROOTD_VMP=$(stashcp --closest | cut -d'/' -f3):/stash=/
        fi
    elif [[ "x$STASHCACHE" = "x1"  ||  "x$STASHCACHE_WRITABLE" = "x1" ]]; then
        setup_stashcp
        # No more extra path for $STASHCACHE_WRITABLE
        # [[ $? -eq 0 ]] && [[ "x$STASHCACHE_WRITABLE" = "x1" ]]export PATH="/cvmfs/oasis.opensciencegrid.org/osg/projects/stashcp/writeback:$PATH"
    fi
    
    
    ################################
    #
    #  Load user specified modules
    #
    if [[ "X$LoadModules" != "X" ]]; then
        if [[ "x$MODULE_USE" != "x1" ]]; then
            warn "Module unavailable. Unable to load desired modules: $LoadModules"
        else
            ModuleList=$(echo $LoadModules | sed 's/^LoadModules = //i;s/"//g')
            for Module in $ModuleList; do
                info_dbg "Loading module: $Module"
                module load "$Module"
            done
        fi
    fi
fi


# TODO: This is OSG specific. Should there be something similar in GWMS?
###############################
#
#  Trace callback
#
#
#if [ ! -e .trace-callback ]; then
#    (wget -nv -O .trace-callback http://osg-vo.isi.edu/osg/agent/trace-callback && chmod 755 .trace-callback) >/dev/null 2>&1 || /bin/true
#fi
#./.trace-callback start >/dev/null 2>&1 || /bin/true
#rm -f .trace-callback >/dev/null 2>&1 || true

##############################
#
#  Cleanup
#
# Aux dir in the future mounted read only. Remove the directory if in Singularity
# TODO: should always auxdir be copied and removed? Should be left for the job?
[[ "$GWMS_AUX_SUBDIR/" == /srv/* ]] && rm -rf "$GWMS_AUX_SUBDIR/" >/dev/null 2>&1 || true
rm -f .gwms-user-job-wrapper.sh >/dev/null 2>&1 || true

##############################
#
#  Run the real job
#
info_dbg "current directory at execution ($(pwd)): $(ls -al)"
info_dbg "GWMS singularity wrapper, job exec: $*"
info_dbg "GWMS singularity wrapper, messages after this line are from the actual job ##################"
exec "$@"
error=$?
# exec failed. Log, communicate to HTCondor, avoid black hole and exit
exit_wrapper "exec failed  (Singularity:$GWMS_SINGULARITY_REEXEC, exit code:$error): $*" $error
