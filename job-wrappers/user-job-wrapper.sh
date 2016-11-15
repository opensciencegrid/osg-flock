#!/bin/bash

# singularity is a module on some sites
module load singularity >/dev/null 2>&1 || /bin/true

# make sure the job can access certain information via the environment, for example ProjectName
export OSGVO_PROJECT_NAME=`(grep -i '^ProjectName' $_CONDOR_JOB_AD | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
export OSGVO_SUBMITTER=`(grep -i '^User ' $_CONDOR_JOB_AD | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`

# prepend HTCondor libexec dir so that we can call chirp
if [ -e ../../main/condor/libexec ]; then
    DER=`(cd ../../main/condor/libexec; pwd)`
    export PATH=$DER:$PATH
fi

# load modules, if available
if [ -e /cvmfs/oasis.opensciencegrid.org/osg/modules/lmod/current/init/bash ]; then
    . /cvmfs/oasis.opensciencegrid.org/osg/modules/lmod/current/init/bash 
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

StashCache=(`grep ^WantsStashCache $_CONDOR_JOB_AD`)
PosixStashCache=(`grep ^WantsPosixStashCache $_CONDOR_JOB_AD`)
 
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

LoadModules=`grep ^LoadModules $_CONDOR_JOB_AD 2>/dev/null`

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
#  fall through to next/default job wrapper
#

