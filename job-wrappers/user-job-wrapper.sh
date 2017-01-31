#!/bin/bash


function getPropBool
{
    # $1 the file (for example, $_CONDOR_JOB_AD or $_CONDOR_MACHINE_AD)
    # $2 the key
    # return is "1" for true, "0" for false/unspecified
    val=`(grep -i "^$2 " $1 | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    # convert variations of true to 1
    if (echo "x$val" | grep -i true) >/dev/null 2>&1; then
        val="1"
    fi
    if [ "x$val" = "x" ]; then
        val="0"
    fi
    echo $val
    # return value accordingly, but backwards (true=>0, false=>1)
    if [ "$val" = "1" ];  then
        return 0
    else:
        return 1
    fi
}


if [ "x$SINGULARITY_REEXEC" = "x" ]; then
    
    if [ "x$_CONDOR_JOB_AD" = "x" ]; then
        export _CONDOR_JOB_AD="NONE"
    fi
    if [ "x$_CONDOR_MACHINE_AD" = "x" ]; then
        export _CONDOR_MACHINE_AD="NONE"
    fi

    # make sure the job can access certain information via the environment, for example ProjectName
    export OSGVO_PROJECT_NAME=`(grep -i '^ProjectName ' $_CONDOR_JOB_AD | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    export OSGVO_SUBMITTER=`(grep -i '^User ' $_CONDOR_JOB_AD | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    
    # "save" some setting from the condor ads - we need these even if we get re-execed
    # inside singularity in which the paths in those env vars are wrong
    # Seems like arrays do not survive the singularity transformation, so set them
    # explicity

    export HAS_SINGULARITY=$(getPropBool $_CONDOR_MACHINE_AD HAS_SINGULARITY)

    export SINGULARITY_PATH=`(grep -i '^SINGULARITY_PATH' $_CONDOR_MACHINE_AD | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`

    export STASHCACHE=$(getPropBool $_CONDOR_JOB_AD WantsStashCache)

    export POSIXSTASHCACHE=$(getPropBool $_CONDOR_JOB_AD WantsPosixStashCache)

    export LoadModules=`grep -i ^LoadModules $_CONDOR_JOB_AD 2>/dev/null`

    export LMOD_BETA=$(getPropBool $_CONDOR_JOB_AD LMOD_BETA)


    #############################################################################
    #
    #  Singularity
    #
    if [ "x$HAS_SINGULARITY" = 'x1' -a "x$SINGULARITY_PATH" != "x" ]; then

        # TODO: support user supplied images

        # We want to map the full glidein dir to /srv inside the container. This is so 
        # that we can rewrite env vars pointing to somewhere inside that dir (for
        # example, X509_USER_PROXY)
        export SING_OUTSIDE_BASE_DIR=`echo "$PWD" | sed -E "s;(.*/glide_[a-zA-Z0-9]+)/.*;\1;"`
        export SING_INSIDE_EXEC_DIR=`echo "$PWD" | sed -E "s;.*/glide_[a-zA-Z0-9]+/(.*);/srv/\1;"`

        # build a new command line, with updated paths
        CMD=""
        for VAR in $0 "$@"; do
            VAR=`echo " $VAR" | sed -E "s;.*/glide_[a-zA-Z0-9]+/(.*);/srv/\1;"`
            CMD="$CMD $VAR"
        done

        export SINGULARITY_REEXEC=1
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

# prepend HTCondor libexec dir so that we can call chirp
if [ -e ../../main/condor/libexec ]; then
    DER=`(cd ../../main/condor/libexec; pwd)`
    export PATH=$DER:$PATH
fi

# load modules, if available
if [ "x$LMOD_BETA" = "x1" ]; then
    if [ -e /cvmfs/oasis.opensciencegrid.org/osg/sw/module-beta-init.sh ]; then
        . /cvmfs/oasis.opensciencegrid.org/osg/sw/module-beta-init.sh
    fi
elif [ -e /cvmfs/oasis.opensciencegrid.org/osg/sw/module-init.sh ]; then
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
if [ "x$POSIXSTASHCACHE" = "x1" ]; then
  setup_stashcp
 
  # Add the LD_PRELOAD hook
  export LD_PRELOAD=$MODULE_XROOTD_BASE/lib64/libXrdPosixPreload.so:$LD_PRELOAD
 
  # Set proxy for virtual mount point
  # Format: cache.domain.edu/local_mount_point=/storage_path
  # E.g.: export XROOTD_VMP=data.ci-connect.net:/stash=/
  # Currently this points _ONLY_ to the OSG Connect source server
  export XROOTD_VMP=$(stashcp --closest | cut -d'/' -f3):/stash=/
 
elif [ "x$STASHCACHE" = 'x1' ]; then
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



