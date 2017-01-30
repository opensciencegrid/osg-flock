#!/bin/bash

if [ "x$SINGULARITY_REEXEC" = "x" ]; then

    # singularity is a module on some sites
    module load singularity >/dev/null 2>&1 || /bin/true
    
    if [ "x$_CONDOR_JOB_AD" = "x" ]; then
        export _CONDOR_JOB_AD="NONE"
    fi
    if [ "x$_CONDOR_MACHINE_AD" = "x" ]; then
        export _CONDOR_MACHINE_AD="NONE"
    fi

    # make sure the job can access certain information via the environment, for example ProjectName
    export OSGVO_PROJECT_NAME=`(grep -i '^ProjectName' $_CONDOR_JOB_AD | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    export OSGVO_SUBMITTER=`(grep -i '^User ' $_CONDOR_JOB_AD | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    
    # prepend HTCondor libexec dir so that we can call chirp
    if [ -e ../../main/condor/libexec ]; then
        DER=`(cd ../../main/condor/libexec; pwd)`
        export PATH=$DER:$PATH
    fi

    # "save" some setting from the condor ads - we need these even if we get re-execed
    # inside singularity in which the paths in those env vars are wrong
    export HAS_SINGULARITY=(`grep ^HAS_SINGULARITY $_CONDOR_MACHINE_AD`)
    export SINGULARITY_PATH=`(grep -i '^SINGULARITY_PATH' $_CONDOR_MACHINE_AD | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    export StashCache=(`grep ^WantsStashCache $_CONDOR_JOB_AD`)
    export PosixStashCache=(`grep ^WantsPosixStashCache $_CONDOR_JOB_AD`)
    export LoadModules=(`grep ^LoadModules $_CONDOR_JOB_AD`)


    #############################################################################
    #
    #  Singularity
    #
    if [ "x${HAS_SINGULARITY[2]}" == 'xtrue' -a "x$SINGULARITY_PATH" != "x" ]; then

        # TODO: support user supplied images

        # We want to map the full glidein dir to /srv inside the container. This is so 
        # that we can rewrite env vars pointing to somewhere inside that dir (for
        # example, X509_USER_PROXY)
        export SING_OUTSIDE_BASE_DIR=`echo "$PWD" | sed -E "s;(.*/glide_[a-zA-Z0-9]+)/.*;\1;"`
        export SING_INSIDE_EXEC_DIR=`echo "$PWD" | sed -E "s;.*/glide_[a-zA-Z0-9]+/(.*);/srv/\1;"`

        # build a new command line, with updated paths
        CMD=""
        for VAR in "$@"; do
            VAR=`echo " $VAR" | sed -E "s;.*/glide_[a-zA-Z0-9]+/(.*);/srv/\1;"`
            CMD="$CMD $VAR"
        done

        export SINGULARITY_REEXEC=1
        echo "$SINGULARITY_PATH exec --bind /cvmfs --bind $SING_OUTSIDE_BASE_DIR:/srv --pwd $SING_INSIDE_EXEC_DIR --scratch /var/tmp --scratch /tmp --containall /cvmfs/cernvm-prod.cern.ch/cvm3/ $CMD" >&2
        exec $SINGULARITY_PATH exec --bind /cvmfs --bind $SING_OUTSIDE_BASE_DIR:/srv --pwd $SING_INSIDE_EXEC_DIR --scratch /var/tmp --scratch /tmp --containall /cvmfs/cernvm-prod.cern.ch/cvm3/ $CMD
    fi

else
    # we are now inside singularity - fix up the env
    unset TMP
    unset TEMP
    unset X509_CERT_DIR
    for key in X509_USER_PROXY X509_USER_CERT _CONDOR_MACHINE_AD _CONDOR_JOB_AD ; do
        eval val="\$$key"
        val=`echo "$val" | sed -E "s;.*/glide_[a-zA-Z0-9]+/(.*);/srv/\1;"`
        eval $key=$val
    done
fi 



#############################################################################
#
#  modules and env 
#

# load modules, if available
if [ -e /cvmfs/oasis.opensciencegrid.org/osg/sw/module-init.sh ]; then
    . /cvmfs/oasis.opensciencegrid.org/osg/sw/module-init.sh
fi


# fix discrepancy for Squid proxy URLs
if [ "x$GLIDEIN_Proxy_URL" = "x" -o "$GLIDEIN_Proxy_URL" = "None" ]; then
    if [ "x$OSG_SQUID_LOCATION" != "x" -a "$OSG_SQUID_LOCATION" != "None" ]; then
        export GLIDEIN_Proxy_URL="$OSG_SQUID_LOCATION"
    fi
fi


#############################################################################
#
#  Stash cache 
#

function setup_stashcp {
  module load stashcp
 
  # Determine XRootD plugin directory.
  # in lieu of a MODULE_<name>_BASE from lmod, this will do:
  export MODULE_XROOTD_BASE=$(which xrdcp | sed -e 's,/bin/.*,,')
  export XRD_PLUGINCONFDIR=$MODULE_XROOTD_BASE/etc/xrootd/client.plugins.d
 
}
 
# Check for PosixStashCache first
if [[ ${PosixStashCache[2]} == 'true' || "${PosixStashcache[2]}" == '1' ]]; then
  setup_stashcp
 
  # Add the LD_PRELOAD hook
  export LD_PRELOAD=$MODULE_XROOTD_BASE/lib64/libXrdPosixPreload.so:$LD_PRELOAD
 
  # Set proxy for virtual mount point
  # Format: cache.domain.edu/local_mount_point=/storage_path
  # E.g.: export XROOTD_VMP=data.ci-connect.net:/stash=/
  # Currently this points _ONLY_ to the OSG Connect source server
  export XROOTD_VMP=$(stashcp --closest | cut -d'/' -f3):/stash=/
 
elif [[ "${StashCache[2]}" == 'true' || "${StashCache[2]}" == '1' ]]; then
  setup_stashcp
 
fi


#############################################################################
#
#  Load user specified modules
#

if [ "X$LoadModules" != "X" ]; then
    ModuleList=`echo $LoadModules | sed 's/^LoadModules = //i' | sed 's/"//g'`
    for Module in $ModuleList; do
        module load $Module
    done
fi


#############################################################################
#
#  Trace callback
#

if [ ! -e ../../trace-callback ]; then
    (wget -nv -O ../../trace-callback http://obelix.isi.edu/osg/agent/trace-callback && chmod 755 ../../trace-callback) >/dev/null 2>&1 || /bin/true
fi
../../trace-callback start >/dev/null 2>&1 || /bin/true


#############################################################################
#
#  Run the real job
#
exec "$@"
error=$?
echo "Failed to exec($error): $@" > $_CONDOR_WRAPPER_ERROR_FILE
exit 1



