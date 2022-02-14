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

    # signal other parts of the glidein that it is time to stop accepting jobs
    touch $GWMS_THIS_SCRIPT_DIR/stop-glidein.stamp >/dev/null 2>&1

    # Publish the error so that HTCondor understands that is a wrapper error and retries the job
    if [[ -n "$_CONDOR_WRAPPER_ERROR_FILE" ]]; then
        warn "Wrapper script failed, creating condor log file: $_CONDOR_WRAPPER_ERROR_FILE"
        echo "Wrapper script $GWMS_THIS_SCRIPT failed ($exit_code): $1" >> $_CONDOR_WRAPPER_ERROR_FILE
    else
        publish_fail="HTCondor error file"
    fi
    
    [[ -n "$publish_fail" ]] && warn "Failed to communicate ERROR with ${publish_fail}"

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
    export glidein_config="$GWMS_THIS_SCRIPT_DIR/glidein_config"

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
    echo "ERROR: $GWMS_THIS_SCRIPT: Unable to find GWMS_DIR! (GWMS_THIS_SCRIPT_DIR=$GWMS_THIS_SCRIPT_DIR GWMS_SUBDIR=$GWMS_SUBDIR)" 1>&2
    exit_wrapper "Wrapper script $GWMS_THIS_SCRIPT failed: Unable to find GWMS_DIR! (GWMS_THIS_SCRIPT_DIR=$GWMS_THIS_SCRIPT_DIR GWMS_SUBDIR=$GWMS_SUBDIR)" 1
fi
export GWMS_DIR

# Calculating full version number, including md5 sums form the wrapper and singularity_lib
GWMS_VERSION_SINGULARITY_WRAPPER="${GWMS_VERSION_SINGULARITY_WRAPPER}_$(md5sum "$GWMS_THIS_SCRIPT" 2>/dev/null | cut -d ' ' -f1)_$(md5sum "${GWMS_AUX_DIR}/singularity_lib.sh" 2>/dev/null | cut -d ' ' -f1)"
info_dbg "GWMS singularity wrapper ($GWMS_VERSION_SINGULARITY_WRAPPER) starting, $(date). Imported singularity_lib.sh. glidein_config ($glidein_config)."
info_dbg "$GWMS_THIS_SCRIPT, in $(pwd), list: $(ls -al)"

function get_glidein_config_value {
    # extracts a config attribute value from
    # $1 is the attribute key
    CF=$glidein_config
    KEY="$1"
    VALUE=`(cat $CF | grep "^$KEY " | tail -n 1 | sed "s/^$KEY //") 2>/dev/null`
    echo "$VALUE"
}

# OS Pool helpers
# source our helpers
if [[ $GWMS_SINGULARITY_REEXEC -ne 1 ]]; then
    group_dir=$(get_glidein_config_value GLIDECLIENT_GROUP_WORK_DIR)
    if [ -e "$group_dir/itb-ospool-lib" ]; then
        source "$group_dir/itb-ospool-lib"
    else
        source "$group_dir/ospool-lib"
    fi
fi


download_or_build_singularity_image () {
    local singularity_image="$1"

    # ALLOW_NONCVMFS_IMAGES determines the approach here
    # if it is 0, verify that the image is indeed on CVMFS
    # if it is 1, transform the image to a form and try downloaded it from our services

    # In addition, UNPACK_SIF determines whether a downloaded SIF image is
    # expanded into the sandbox format (1) or used as-is (0).

    if [ "x$ALLOW_NONCVMFS_IMAGES" = "x0" ]; then
        if ! (echo "$singularity_image" | grep "^/cvmfs/") >/dev/null 2>&1; then
            info_dbg "The specified image $singularity_image is not on CVMFS. Continuing anyways."
            # allow this for now - we have user who ship images with their jobs
            #return 1
        fi
    else
        # first figure out a base image name in the form of owner/image:tag, then
        # transform it to our expected image and name and try to download
        singularity_srcs=""

        if [[ $singularity_image = /cvmfs/singularity.opensciencegrid.org/* ]]; then
            # transform /cvmfs to a set or URLS to to try
            base_name=$(echo $singularity_image | sed 's;/cvmfs/singularity.opensciencegrid.org/;;' | sed 's;/*/$;;')
            image_name=$(echo "$base_name" | sed 's;[:/];__;g')
            week=$(date +'%V')
            singularity_srcs="stash:///osgconnect/public/rynge/infrastructure/images/$week/sif/$image_name.sif https://data.isi.edu/osg/images/$image_name.sif docker://hub.opensciencegrid.org/$base_name docker://$base_name"
        elif [[ -e "$singularity_image" ]]; then
            # the image is not on cvmfs, but has already been downloaded - short circuit here
            echo "$singularity_image"
            return 0
        else 
            # user has been explicit with for example a docker or http URL
            image_name=$(echo "$singularity_image" | sed 's;^[[:alnum:]]*://;;' | sed 's;[:/];__;g')
            singularity_srcs="$singularity_image"
        fi
        # at this point image_name should be something like "opensciencegrid__osgvo-el8__latest"

        local image_path="$GWMS_THIS_SCRIPT_DIR/images/$image_name"
        # simple lock to prevent multiple slots from attempting dowloading of the same image
        local lockfile="$image_path.lock"
        local waitcount=0
        while [[ -e $lockfile && $waitcount -lt 10 ]]; do
            sleep 60s
            waitcount=$(($waitcount + 1))
        done

        # already downloaded?
        if [[ -e "$image_path" ]]; then
            # even if we can use the sif, if we already have the sandbox, use that
            echo "$image_path"
            return 0
        elif [[ -e "$image_path.sif" && $UNPACK_SIF = 0 ]]; then
            # we already have the sif and we can use it
            echo "$image_path.sif"
            return 0
        else
            local tmptarget="$image_path.$$"
            local logfile="$image_path.log"
            local downloaded=0
            touch $lockfile
            rm -f $logfile

            if [[ -e "$image_path.sif" && $UNPACK_SIF = 1 ]]; then
                # we already have the sif but need to unpack it
                # (this shouldn't happen very often)
                if ("$GWMS_SINGULARITY_PATH" build --force --sandbox "$tmptarget" "$image_path.sif" ) &>>"$logfile"; then
                    mv "$tmptarget" "$image_path"
                    rm -f "$lockfile" "$image_path.sif"
                    echo "$image_path"
                    return 0
                else
                    # unpack failed - sif may be damaged
                    rm -f "$image_path.sif"
                fi
            fi

            local tmptarget2
            local image_path2
            if [[ $UNPACK_SIF = 0 ]]; then
                tmptarget2=$tmptarget.sif
                image_path2=$image_path.sif
            else
                tmptarget2=$tmptarget
                image_path2=$image_path
            fi

            for src in $singularity_srcs; do
                echo "Trying to download from $src ..." &>>$logfile

                if (echo "$src" | grep "^stash")>/dev/null 2>&1; then
                    if (stash_download "$tmptarget2" "$src") &>>$logfile; then
                        downloaded=1
                        break
                    fi

                elif (echo "$src" | grep "^http")>/dev/null 2>&1; then
                    if (http_download "$tmptarget2" "$src") &>>$logfile; then
                        downloaded=1
                        break
                    fi

                elif (echo "$src" | grep "^docker:" | grep -v "hub.opensciencegrid.org")>/dev/null 2>&1; then
                    # docker is a special case - just pass it through
                    # hub.opensciencegrid.org will be handled by "singularity build/pull" for now
                    rm -f "$lockfile"
                    echo "$src"
                    return 0

                elif (echo "$src" | grep "://")>/dev/null 2>&1; then
                    # some other url
                    if [[ $UNPACK_SIF = 1 ]]; then
                        if ($GWMS_SINGULARITY_PATH build --force --sandbox "$tmptarget2" "$src" ) &>>"$logfile"; then
                            downloaded=1
                            break
                        fi
                    else
                        # "singularity pull" uses less CPU than "singularity build"
                        # but $src must be a URL and it can't do --sandbox
                        if ($GWMS_SINGULARITY_PATH pull --force "$tmptarget2" "$src" ) &>>"$logfile"; then
                            downloaded=1
                            break
                        fi
                    fi

                else
                    # we shouldn't have a local path at this point
                    warn "Unexpected non-URL source '$src' for image $singularity_image"

                fi
                # clean up between attempts
                rm -rf "$tmptarget2"
            done
            if [[ $downloaded = 1 ]]; then
                mv "$tmptarget2" "$image_path2"
            else
                warn "Unable to download or build image ($singularity_image); logs:"
                cat "$logfile" >&2
                rm -rf "$tmptarget2" "$lockfile"
                return 1
            fi
            singularity_image=$image_path2
            rm -f "$lockfile"
        fi
    fi
    echo "$singularity_image"
    return 0
}


# OSGVO - overrideing this from singularity_lib.sh
singularity_prepare_and_invoke() {
    # Code moved into a function to allow early return in case of failure
    # In case of failure: 1. it invokes singularity_exit_or_fallback which exits if Singularity is required
    #   2. it interrupts itself and returns anyway
    # The function returns in case the Singularity setup fails 
    # In:
    #   SINGULARITY_IMAGES_DICT: dictionary w/ Singularity images
    #   $SINGULARITY_IMAGE_RESTRICTIONS: constraints on the Singularity image
    # Using:
    #   GWMS_SINGULARITY_IMAGE, 
    #   or GWMS_SINGULARITY_IMAGE_RESTRICTIONS (SINGULARITY_IMAGES_DICT via singularity_get_image)
    #      DESIRED_OS, GLIDEIN_REQUIRED_OS, REQUIRED_OS
    #   $OSG_SITE_NAME (in monitoring)
    #   GWMS_THIS_SCRIPT 
    #   $GLIDEIN_Tmp_Dir GWMS_SINGULARITY_EXTRA_OPTS 
    #   GWMS_SINGULARITY_OUTSIDE_PWD_LIST GWMS_SINGULARITY_OUTSIDE_PWD GWMS_THIS_SCRIPT_DIR _CONDOR_JOB_IWD
    #   GWMS_BASE_SUBDIR - if defined will be bound to the glidein directory (will be accessible from singularity)
    # Out:
    #   GWMS_SINGULARITY_IMAGE GWMS_SINGULARITY_IMAGE_HUMAN GWMS_SINGULARITY_OUTSIDE_PWD_LIST SINGULARITY_WORKDIR GWMS_SINGULARITY_EXTRA_OPTS GWMS_SINGULARITY_REEXEC
    # If  image is not provided, load the default one
    # Custom URIs: http://singularity.lbl.gov/user-guide#supported-uris
    
    # Choose the singularity image
    if [[ -z "$GWMS_SINGULARITY_IMAGE" ]]; then
        # No image requested by the job
        # Use OS matching to determine default; otherwise, set to the global default.
        #  # Correct some legacy names? What if they are used in the dictionary?
        #  REQUIRED_OS="`echo ",$REQUIRED_OS," | sed "s/,el7,/,rhel7,/;s/,el6,/,rhel6,/;s/,+/,/g;s/^,//;s/,$//"`"
        DESIRED_OS=$(list_get_intersection "${GLIDEIN_REQUIRED_OS:-any}" "${REQUIRED_OS:-any}")
        if [[ -z "$DESIRED_OS" ]]; then
            msg="ERROR   VO (or job) REQUIRED_OS and Entry GLIDEIN_REQUIRED_OS have no intersection. Cannot select a Singularity image."
            singularity_exit_or_fallback "$msg" 1
            return
        fi
        if [[ "x$DESIRED_OS" = xany ]]; then
            # Prefer the platforms default,rhel7,rhel6,rhel8, otherwise pick the first one available
            GWMS_SINGULARITY_IMAGE=$(singularity_get_image default,rhel7,rhel6,rhel8 ${GWMS_SINGULARITY_IMAGE_RESTRICTIONS:+$GWMS_SINGULARITY_IMAGE_RESTRICTIONS,}any)
        else
            GWMS_SINGULARITY_IMAGE=$(singularity_get_image "$DESIRED_OS" $GWMS_SINGULARITY_IMAGE_RESTRICTIONS)
        fi
    fi

    # At this point, GWMS_SINGULARITY_IMAGE is still empty, something is wrong
    if [[ -z "$GWMS_SINGULARITY_IMAGE" ]]; then
        msg="\
ERROR   If you get this error when you did not specify required OS, your VO does not support any valid default Singularity image
        If you get this error when you specified required OS, your VO does not support any valid image for that OS"
        singularity_exit_or_fallback "$msg" 1
        return
    fi

    # TODO: Custom images are not subject to SINGULARITY_IMAGE_RESTRICTIONS in OSG and CMS scripts. Should add a check here?
    #if ! echo "$GWMS_SINGULARITY_IMAGE" | grep ^"/cvmfs" >/dev/null 2>&1; then
    #    exit_wrapper "ERROR: $GWMS_SINGULARITY_IMAGE is not in /cvmfs area. Exiting" 1
    #fi

    # Whether user-provided or default image, we make sure it exists and make sure CVMFS has not fallen over
    # TODO: better -e or ls?
    #if ! ls -l "$GWMS_SINGULARITY_IMAGE/" >/dev/null; then
    #if [[ ! -e "$GWMS_SINGULARITY_IMAGE" ]]; then
    # will both work for non expanded images?

    # check that the image is actually available (but only for /cvmfs ones)
    if cvmfs_path_in_cvmfs "$GWMS_SINGULARITY_IMAGE"; then
        if ! ls -l "$GWMS_SINGULARITY_IMAGE" >/dev/null; then
            msg="\
ERROR   Unable to access the Singularity image: $GWMS_SINGULARITY_IMAGE
        Site and node: $OSG_SITE_NAME $(hostname -f)"
            singularity_exit_or_fallback "$msg" 1 10m
            return
        fi
    fi

    if [[ "$GWMS_SINGULARITY_IMAGE" != *://* && ! -e "$GWMS_SINGULARITY_IMAGE" ]]; then
        msg="\
ERROR   Unable to access the Singularity image: $GWMS_SINGULARITY_IMAGE
        Site and node: $OSG_SITE_NAME $(hostname -f)"
        singularity_exit_or_fallback "$msg" 1 10m
        return
    fi

    # Put a human readable version of the image in the env before expanding it - useful for monitoring
    export GWMS_SINGULARITY_IMAGE_HUMAN="$GWMS_SINGULARITY_IMAGE"

    # for /cvmfs based directory images, expand the path without symlinks so that
    # the job can stay within the same image for the full duration
    if cvmfs_path_in_cvmfs "$GWMS_SINGULARITY_IMAGE"; then
        # Make sure CVMFS is mounted in Singularity
        export GWMS_SINGULARITY_BIND_CVMFS=1
        if (cd "$GWMS_SINGULARITY_IMAGE") >/dev/null 2>&1; then
            # This will fail for images that are not expanded in CVMFS, just ignore the failure
            local new_image_path
            new_image_path=$( (cd "$GWMS_SINGULARITY_IMAGE" && pwd -P) 2>/dev/null )
            if [[ -n "$new_image_path" ]]; then
                GWMS_SINGULARITY_IMAGE=$new_image_path
            fi
        fi
    fi

    info_dbg "using image $GWMS_SINGULARITY_IMAGE_HUMAN ($GWMS_SINGULARITY_IMAGE)"
    # Singularity image is OK, continue w/ other init

    # set up the env to make sure Singularity uses the glidein dir for exported /tmp, /var/tmp
    if [[ -n "$GLIDEIN_Tmp_Dir"  &&  -e "$GLIDEIN_Tmp_Dir" ]]; then
        if mkdir "$GLIDEIN_Tmp_Dir/singularity-work.$$" ; then
            export SINGULARITY_WORKDIR="$GLIDEIN_Tmp_Dir/singularity-work.$$"
        else
            warn "Unable to set SINGULARITY_WORKDIR to $GLIDEIN_Tmp_Dir/singularity-work.$$. Leaving it undefined."
        fi
    fi

    GWMS_SINGULARITY_EXTRA_OPTS="$GLIDEIN_SINGULARITY_OPTS"

    # Binding different mounts (they will be removed if not existent on the host)
    # This is a dictionary in string w/ singularity mount options ("src1[:dst1[:opt1]][,src2[:dst2[:opt2]]]*"
    # OSG: checks also in image, may not work if not expanded. And Singularity will not fail if missing, only give a warning
    #  if [ -e $MNTPOINT/. -a -e $OSG_SINGULARITY_IMAGE/$MNTPOINT ]; then
    GWMS_SINGULARITY_WRAPPER_BINDPATHS_DEFAULTS="/hadoop,/ceph,/hdfs,/lizard,/mnt/hadoop,/mnt/hdfs,/etc/hosts,/etc/localtime"

    # CVMFS access inside container (default, but optional)
    if [[ "x$GWMS_SINGULARITY_BIND_CVMFS" = "x1" ]]; then
        GWMS_SINGULARITY_WRAPPER_BINDPATHS_DEFAULTS="`dict_set_val GWMS_SINGULARITY_WRAPPER_BINDPATHS_DEFAULTS /cvmfs`"
    fi

    # GPUs - bind outside OpenCL directory if available, and add --nv flag
    if [[ "$OSG_MACHINE_GPUS" -gt 0  ||  "x$GPU_USE" = "x1" ]]; then
        if [[ -e /etc/OpenCL/vendors ]]; then
            GWMS_SINGULARITY_WRAPPER_BINDPATHS_DEFAULTS="`dict_set_val GWMS_SINGULARITY_WRAPPER_BINDPATHS_DEFAULTS /etc/OpenCL/vendors /etc/OpenCL/vendors`"
        fi
        GWMS_SINGULARITY_EXTRA_OPTS="$GWMS_SINGULARITY_EXTRA_OPTS --nv"
    fi
    info_dbg "bind-path default (cvmfs:$GWMS_SINGULARITY_BIND_CVMFS, hostlib:`[ -n "$HOST_LIBS" ] && echo 1`, ocl:`[ -e /etc/OpenCL/vendors ] && echo 1`): $GWMS_SINGULARITY_WRAPPER_BINDPATHS_DEFAULTS"

    # We want to bind $PWD to /srv within the container - however, in order
    # to do that, we have to make sure everything we need is in $PWD, most
    # notably $GWMS_DIR (bin, lib, ...), the user-job-wrapper.sh (this script!) 
    # and singularity_lib.sh (in $GWMS_AUX_SUBDIR)
    #
    # If gwms dir is present, then copy it inside the container
    [[ -z "$GWMS_SUBDIR" ]] && { GWMS_SUBDIR=".gwms.d"; warn "GWMS_SUBDIR was undefined, setting to '.gwms.d'"; }
    local gwms_dir=${GWMS_DIR:-"../../$GWMS_SUBDIR"}
    if [[ -d "$gwms_dir" ]]; then
        if mkdir -p "$GWMS_SUBDIR" && cp -r "$gwms_dir"/* "$GWMS_SUBDIR/"; then
            # Should copy only lib and bin instead?
            # TODO: change the message when condor_chirp requires no more special treatment
            info_dbg "copied GlideinWMS utilities (bin and libs, including condor_chirp) inside the container ($(pwd)/$GWMS_SUBDIR)"
        else
            warn "Unable to copy GlideinWMS utilities inside the container (to $(pwd)/$GWMS_SUBDIR)"
        fi
    else
        warn "Unable to find GlideinWMS utilities ($gwms_dir from $(pwd))"
    fi
    # copy singularity_lib.sh (in $GWMS_AUX_SUBDIR)
    mkdir -p "$GWMS_AUX_SUBDIR"
    cp "${GWMS_AUX_DIR}/singularity_lib.sh" "$GWMS_AUX_SUBDIR/"       
    # mount the original glidein directory (for setup scripts only, not jobs)
    if [[ -n "$GWMS_BASE_SUBDIR" ]]; then
        # Make the glidein directory visible in singularity
        mkdir -p "$GWMS_BASE_SUBDIR"
        GWMS_SINGULARITY_WRAPPER_BINDPATHS_OVERRIDE="${GWMS_SINGULARITY_WRAPPER_BINDPATHS_OVERRIDE:+${GWMS_SINGULARITY_WRAPPER_BINDPATHS_OVERRIDE},}$( dirname "${GWMS_THIS_SCRIPT_DIR}"):/srv/$GWMS_BASE_SUBDIR"
    fi
    # copy the wrapper.sh (this script!)
    if [[ "$GWMS_THIS_SCRIPT" == */main/singularity_wrapper.sh ]]; then
        export JOB_WRAPPER_SINGULARITY="/srv/$GWMS_BASE_SUBDIR/main/singularity_wrapper.sh"
    else
        cp "$GWMS_THIS_SCRIPT" .gwms-user-job-wrapper.sh
        export JOB_WRAPPER_SINGULARITY="/srv/.gwms-user-job-wrapper.sh"
    fi

    # Remember what the outside pwd dir is so that we can rewrite env vars
    # pointing to somewhere inside that dir (for example, X509_USER_PROXY)
    #if [[ -n "$_CONDOR_JOB_IWD" ]]; then
    #    export GWMS_SINGULARITY_OUTSIDE_PWD="$_CONDOR_JOB_IWD"
    #else
    #    export GWMS_SINGULARITY_OUTSIDE_PWD="$PWD"
    #fi
    # Should this be GWMS_THIS_SCRIPT_DIR?
    #   Problem at sites like MIT where the job is started in /condor/execute/.. hard link from
    #   /export/data1/condor/execute/...
    # Do not trust _CONDOR_JOB_IWD when it comes to finding pwd for the job - M.Rynge
    GWMS_SINGULARITY_OUTSIDE_PWD="$PWD"
    # Protect from jobs starting from linked or bind mounted directories
    for i in "$_CONDOR_JOB_IWD" "$GWMS_THIS_SCRIPT_DIR"; do
        if [[ "$i" != "$GWMS_SINGULARITY_OUTSIDE_PWD" ]]; then
            [[ "$(robust_realpath "$i")" == "$GWMS_SINGULARITY_OUTSIDE_PWD" ]] && GWMS_SINGULARITY_OUTSIDE_PWD="$i"
        fi
    done
    export GWMS_SINGULARITY_OUTSIDE_PWD="$GWMS_SINGULARITY_OUTSIDE_PWD"
    GWMS_SINGULARITY_OUTSIDE_PWD_LIST="$(singularity_make_outside_pwd_list \
        "${GWMS_SINGULARITY_OUTSIDE_PWD_LIST}" "${PWD}" "$(robust_realpath "${PWD}")" \
        "${GWMS_THIS_SCRIPT_DIR}" "${_CONDOR_JOB_IWD}")"
    export GWMS_SINGULARITY_OUTSIDE_PWD_LIST

    # Build a new command line, with updated paths. Returns an array in GWMS_RETURN
    singularity_update_path /srv "$@"

    # Get Singularity binds, uses also GLIDEIN_SINGULARITY_BINDPATH, GLIDEIN_SINGULARITY_BINDPATH_DEFAULT
    # remove binds w/ non existing src (e)
    local singularity_binds
    singularity_binds=$(singularity_get_binds e "$GWMS_SINGULARITY_WRAPPER_BINDPATHS_DEFAULTS" "$GWMS_SINGULARITY_WRAPPER_BINDPATHS_OVERRIDE")
    # Run and log the Singularity command.
    info_dbg "about to invoke singularity, pwd is $PWD"
    export GWMS_SINGULARITY_REEXEC=1

    # Always disabling outside LD_LIBRARY_PATH, PATH, PYTHONPATH and LD_PRELOAD to avoid problems w/ different OS
    # Singularity is supposed to handle this, but different versions behave differently
    # Restore them only if continuing after the exec of singularity failed (end of this function)
    local old_ld_library_path=
    if [[ -n "$LD_LIBRARY_PATH" ]]; then
        old_ld_library_path=$LD_LIBRARY_PATH
        info_dbg "GWMS Singularity wrapper: LD_LIBRARY_PATH is set to $LD_LIBRARY_PATH outside Singularity. This will not be propagated to inside the container instance." 1>&2
        unset LD_LIBRARY_PATH
    fi
    local old_path=
    #if [[ -n "$PATH" ]]; then
    #    old_path=$PATH
    #    info_dbg "GWMS Singularity wrapper: PATH is set to $PATH outside Singularity. This will not be propagated to inside the container instance." 1>&2
    #    unset PATH
    #fi
    local old_pythonpath=
    if [[ -n "$PYTHONPATH" ]]; then
        old_pythonpath=$PYTHONPATH
        info_dbg "GWMS Singularity wrapper: PYTHONPATH is set to $PYTHONPATH outside Singularity. This will not be propagated to inside the container instance." 1>&2
        unset PYTHONPATH
    fi
    if [[ -n "$LD_PRELOAD" ]]; then
        old_ld_preload=$LD_PRELOAD
        info_dbg "GWMS Singularity wrapper: LD_PRELOAD is set to $LD_PRELOAD outside Singularity. This will not be propagated to inside the container instance." 1>&2
        unset LD_PRELOAD
    fi

    # Add --clearenv if requested
    GWMS_SINGULARITY_EXTRA_OPTS=$(env_clear "${GLIDEIN_CONTAINER_ENV}" "${GWMS_SINGULARITY_EXTRA_OPTS}")

    # If there is clearenv protect the variables (it may also have been added by the custom Singularity options)
    if env_gets_cleared "${GWMS_SINGULARITY_EXTRA_OPTS}" ; then
        env_preserve "${GLIDEIN_CONTAINER_ENV}"
    fi

    # The new OSG wrapper is not exec-ing singularity to continue after and inspect if it ran correctly or not
    # This may be causing problems w/ signals (sig-term/quit) propagation - [#24306]
    if [[ -z "$GWMS_SINGULARITY_LIB_VERSION" ]]; then
        # GWMS 3.4.5 or lower, no GWMS_SINGULARITY_GLOBAL_OPTS, no GWMS_SINGULARITY_LIB_VERSION
        singularity_exec "$GWMS_SINGULARITY_PATH" "$GWMS_SINGULARITY_IMAGE" "$singularity_binds" \
                 "$GWMS_SINGULARITY_EXTRA_OPTS" "exec" "$JOB_WRAPPER_SINGULARITY" \
                 "${GWMS_RETURN[@]}"
    else
        singularity_exec "$GWMS_SINGULARITY_PATH" "$GWMS_SINGULARITY_IMAGE" "$singularity_binds" \
                 "$GWMS_SINGULARITY_EXTRA_OPTS" "$GWMS_SINGULARITY_GLOBAL_OPTS" "exec" "$JOB_WRAPPER_SINGULARITY" \
                 "${GWMS_RETURN[@]}"
    fi
    # Continuing here only if exec of singularity failed
    GWMS_SINGULARITY_REEXEC=0
    env_restore "${GLIDEIN_CONTAINER_ENV}"
    # Restoring paths that are always cleared before invoking Singularity, 
    # may contain something used for error communication
    [[ -n "$old_path" ]] && PATH=$old_path
    [[ -n "$old_ld_library_path" ]] && PATH=$old_ld_library_path
    [[ -n "$old_pythonpath" ]] && PYTHONPATH=$old_pythonpath
    [[ -n "$old_ld_preload" ]] && LD_PRELOAD=$old_ld_preload
    # Exit or return to run w/o Singularity
    singularity_exit_or_fallback "exec of singularity failed" $?
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
    #if [[ ",${s_restrictions}," = *",cvmfs,"* ]] && ! cvmfs_path_in_cvmfs "$singularity_image"; then
    #    warn "$singularity_image is not in /cvmfs area as requested"
    #    return 3
    #fi

    # We make sure it exists
    #if [[ ! -e "$singularity_image" ]]; then
    #    warn "ERROR: $singularity_image file not found" 1>&2
    #    return 2
    #fi

    singularity_image=$(download_or_build_singularity_image "$singularity_image") || return 1
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

        # for mksquashfs
        PATH=$PATH:/usr/sbin

        # Should we use CVMFS or pull images directly?
        export ALLOW_NONCVMFS_IMAGES=$(get_prop_bool "$_CONDOR_MACHINE_AD" "ALLOW_NONCVMFS_IMAGES" 0)
        info_dbg "ALLOW_NONCVMFS_IMAGES: $ALLOW_NONCVMFS_IMAGES"

        # Should we use a sif file directly or unpack it first?
        # Rerun the test from osgvo-default-image and warn if the results don't match what's advertised.
        advertised_sif_support=$(get_prop_str "$_CONDOR_MACHINE_AD" "SINGULARITY_CAN_USE_SIF" 0)
        if [[ $advertised_sif_support == "HAS_SINGULARITY" ]]; then
            advertised_sif_support=1
        fi

        UNPACK_SIF=1
        detected_sif_support=0
        if check_singularity_sif_support &>/dev/null; then
            detected_sif_support=1
            UNPACK_SIF=0
        fi
        if [[ $advertised_sif_support != $detected_sif_support ]]; then
            info_dbg "SIF support: advertised SINGULARITY_CAN_USE_SIF ${advertised_sif_support} != detected ${detected_sif_support}; using detected."
        fi
        export UNPACK_SIF

        # OSGVO - disabled for now
        # We make sure that every cvmfs repository that users specify in CVMFSReposList is available, otherwise this script exits with 1
        #cvmfs_test_and_open "$CVMFS_REPOS_LIST" exit_wrapper

        # OSGVO: unset modules leftovers from the site environment 
        clearLmod --quiet 2>/dev/null 
        unset -f spack
        unset -f module
        unset -f ml
        for KEY in \
              ENABLE_LMOD \
              _LMFILES_ \
              LOADEDMODULES \
              MODULESHOME \
              MODULE_USE \
              module \
              switchml \
              $(env | sed 's/=.*//' | egrep "^MODULES_" 2>/dev/null) \
              $(env | sed 's/=.*//' | egrep "^MODULEPATH" 2>/dev/null) \
              $(env | sed 's/=.*//' | egrep "^LMOD" 2>/dev/null) \
              $(env | sed 's/=.*//' | egrep "^SLURM" 2>/dev/null) \
        ; do
            eval VAL="\$$KEY"
            if [ "x$VAL" != "x" ]; then
                info_dbg "Unsetting env var provided by site: $KEY"
            fi
            unset $KEY
        done

        if [ "x$GWMS_SINGULARITY_IMAGE" != "x" ]; then
            # intercept and maybe download the image
            GWMS_SINGULARITY_IMAGE=$(download_or_build_singularity_image "$GWMS_SINGULARITY_IMAGE") || exit 1
        fi

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

gwms_process_scripts "$GWMS_DIR" prejob


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
