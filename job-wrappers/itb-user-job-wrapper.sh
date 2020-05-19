#!/bin/bash


function getPropBool
{
    # $1 the file (for example, $_CONDOR_JOB_AD or $_CONDOR_MACHINE_AD)
    # $2 the key
    # $3 is the default value if unset
    # echo "1" for true, "0" for false/unspecified
    # return 0 for true, 1 for false/unspecified
    default=$3
    if [ "x$default" = "x" ]; then
        default=0
    fi
    val=`(grep -i "^$2 " $1 | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    # convert variations of true to 1
    if (echo "x$val" | grep -i true) >/dev/null 2>&1; then
        val="1"
    fi
    if [ "x$val" = "x" ]; then
        val="$default"
    fi
    echo $val
    # return value accordingly, but backwards (true=>0, false=>1)
    if [ "$val" = "1" ];  then
        return 0
    else
        return 1
    fi
}


function getPropStr
{
    # $1 the file (for example, $_CONDOR_JOB_AD or $_CONDOR_MACHINE_AD)
    # $2 the key
    # $3 default value if unset
    default="$3"
    val=`(grep -i "^$2 " $1 | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    if [ "x$val" = "x" ]; then
        val="$default"
    fi
    echo $val
}


# The following four functions are based mostly on Carl Edquist's code

setmatch () {
  local __=("$@")
  set -- "${BASH_REMATCH[@]}"
  shift
  eval "${__[@]}"
}

rematch () {
  [[ $1 =~ $2 ]] || return 1
  shift 2
  setmatch "$@"
}

get_vars_from_env_str () {
  local str_arr condor_var_string=""
  env_str=${env_str#'"'}
  env_str=${env_str%'"'}
  # Strip out escaped whitespace
  while rematch "$env_str" "(.*)'([[:space:]]+)'(.*)" env_str='$1$3'
  do :; done

  # Now, split the string on whitespace
  read -ra str_arr <<<"${env_str}"

  # Finally, parse each element of the array.
  # They should each be name=value assignments,
  # and we only need to grab the name
  vname_regex="(^[_a-zA-Z][_a-zA-Z0-9]*)(=)[.]*"
  for assign in "${str_arr[@]}"; do
      if [[ "$assign" =~ $vname_regex ]]; then
	  condor_var_string="$condor_var_string ${BASH_REMATCH[1]}"
      fi
  done
  echo "$condor_var_string"
}

parse_env_file () {
    shopt -s nocasematch
    while read -r attr eq env_str; do
	if [[ $attr = Environment && $eq = '=' ]]; then
	    get_vars_from_env_str
	    break
	fi
    done < "$1"
    shopt -u nocasematch
}

shutdown_glidein() {
    # Ian be called when a severe error is encountered. It will
    # result in the glidin stopping taking jobs and eventually
    # shuts down.
    # $1 error message

    echo "$1" 1>&2
    # error to _CONDOR_WRAPPER_ERROR_FILE
    if [ "x$_CONDOR_WRAPPER_ERROR_FILE" != "x" ]; then
        echo "$1" >>$_CONDOR_WRAPPER_ERROR_FILE
    fi
    # chirp
    if [ -e ../../main/condor/libexec/condor_chirp ]; then
        ../../main/condor/libexec/condor_chirp set_job_attr JobWrapperFailure "$1"
    fi
    if [ "x$GWMS_DEBUG" = "x" ]; then
        # if we are not debugging, shutdown
        touch ../../.stop-glidein.stamp >/dev/null 2>&1
        sleep 10m
    fi
    exit 1
}


# ensure all jobs have PATH set
# bash can set a default PATH - make sure it is exported
export PATH=$PATH
if [ "x$PATH" = "x" ]; then
    export PATH="/usr/local/bin:/usr/bin:/bin"
fi

    
if [ "x$_CONDOR_JOB_AD" = "x" ]; then
    export _CONDOR_JOB_AD="NONE"
fi
if [ "x$_CONDOR_MACHINE_AD" = "x" ]; then
    export _CONDOR_MACHINE_AD="NONE"
fi

# make sure the job can access certain information via the environment, for example ProjectName
export OSGVO_PROJECT_NAME=$(getPropStr $_CONDOR_JOB_AD ProjectName)
export OSGVO_SUBMITTER=$(getPropStr $_CONDOR_JOB_AD User)

export STASHCACHE=$(getPropBool $_CONDOR_JOB_AD WantsStashCache 0)
export STASHCACHE_WRITABLE=$(getPropBool $_CONDOR_JOB_AD WantsStashCacheWritable 0)

export POSIXSTASHCACHE=$(getPropBool $_CONDOR_JOB_AD WantsPosixStashCache 0)

# Don't load modules for LIGO
if (echo "X$GLIDEIN_Client" | grep ligo) >/dev/null 2>&1; then
    export InitializeModulesEnv=$(getPropBool $_CONDOR_JOB_AD InitializeModulesEnv 0)
else
    export InitializeModulesEnv=$(getPropBool $_CONDOR_JOB_AD InitializeModulesEnv 1)
fi
export LoadModules=$(getPropStr $_CONDOR_JOB_AD LoadModules)

export LMOD_BETA=$(getPropBool $_CONDOR_JOB_AD LMOD_BETA 0)

export OSG_MACHINE_GPUS=$(getPropStr $_CONDOR_MACHINE_AD GPUs "0")

# http_proxy from our advertise script
export http_proxy=$(getPropStr $_CONDOR_MACHINE_AD http_proxy)
if [ "x$http_proxy" = "x" ]; then
    unset http_proxy
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
if [ "x$InitializeModulesEnv" = "x1" ]; then
    if [ "x$LMOD_BETA" = "x1" ]; then
        # used for testing the new el6/el7 modules 
        if [ -e /cvmfs/oasis.opensciencegrid.org/osg/sw/module-beta-init.sh -a -e /cvmfs/connect.opensciencegrid.org/modules/spack/share/spack/setup-env.sh ]; then
            . /cvmfs/oasis.opensciencegrid.org/osg/sw/module-beta-init.sh
        fi
    elif [ -e /cvmfs/oasis.opensciencegrid.org/osg/sw/module-init.sh -a -e /cvmfs/connect.opensciencegrid.org/modules/spack/share/spack/setup-env.sh ]; then
        . /cvmfs/oasis.opensciencegrid.org/osg/sw/module-init.sh
    fi
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
  # if we do not have stashcp in the path (in the container for example),
  # load stashcache and xrootd from modules
  if ! which stashcp >/dev/null 2>&1; then
      module load stashcache >/dev/null 2>&1 || module load stashcp >/dev/null 2>&1
  fi
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
 
elif [ "x$STASHCACHE" = "x1" -o "x$STASHCACHE_WRITABLE" = "x1" ]; then
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

if [ ! -e .trace-callback ]; then
    (wget -nv -O .trace-callback http://osg-vo.isi.edu/osg/agent/trace-callback && chmod 755 .trace-callback) >/dev/null 2>&1 || /bin/true
fi
./.trace-callback start >/dev/null 2>&1 || /bin/true


#############################################################################
#
#  Cleanup
#

rm -f .trace-callback .osgvo-user-job-wrapper.sh >/dev/null 2>&1 || true


#############################################################################
#
#  Run the real job
#
exec "$@"
error=$?
echo "Failed to exec($error): $@" > $_CONDOR_WRAPPER_ERROR_FILE
exit 1



