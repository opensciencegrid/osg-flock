#!/bin/bash
#
# This is script is mostly the sama script that OSG Frontend uses to
# advertise.
#
# All credits to Mats Rynge (rynge@isi.edu)
#

glidein_config="$1"

                                                           
function info {
    echo "INFO  " $@ 1>&2
}

function warn {
    echo "WARN  " $@ 1>&2
}

function advertise {
    # atype is the type of the value as defined by GlideinWMS:                                                                                           
    #   I - integer                                                                                                                                     
    #   S - quoted string                                                                                                                             
    #   C - unquoted string (i.e. Condor keyword or expression)                                                                                       
                                       
    
    key="$1"
    value="$2"
    atype="$3"

    if [ "$glidein_config" != "NONE" ]; then
        add_config_line $key "$value"
        add_condor_vars_line $key "$atype" "-" "+" "Y" "Y" "+"
    fi

    if [ "$atype" = "S" ]; then
        echo "$key = \"$value\""
    else
        echo "$key = $value"
    fi
}

function get_glidein_config_value {
    # extracts a config attribute value from 
    # $1 is the attribute key
    CF=$glidein_config
    if [ "$glidein_config" = "NONE" ]; then
        CF="$PWD/glidein_config"
    fi
    KEY="$1"
    VALUE=`(cat $CF | grep "^$KEY " | tail -n 1 | sed "s/^$KEY //") 2>/dev/null`
    echo "$VALUE"
}

if [ "x$glidein_config" = "x" ]; then
    glidein_config="NONE"
    info "No arguments provided - assuming HTCondor startd cron mode"
else
    info "Arguments to the script: $@"
fi

info "This is a setup script for the IGWN frontend."
info "In case of problems, contact Edgar Fajardo (emfajard@ucsd.edu)"

if [ "$glidein_config" != "NONE" ]; then
    ###########################################################
    # import advertise and add_condor_vars_line functions
    add_config_line_source=`grep '^ADD_CONFIG_LINE_SOURCE ' $glidein_config | awk '{print $2}'`
    source $add_config_line_source

    condor_vars_file=`grep -i "^CONDOR_VARS_FILE " $glidein_config | awk '{print $2}'`
fi


info "Checking for IGWN container availability"

FS_ATTR="HAS_CVMFS_LIGO_CONTAINERS"
RESULT="False"
if [ -s /cvmfs/ligo-containers.opensciencegrid.org/lscsoft/bayeswave/master ]; then
    RESULT="True"
fi
advertise $FS_ATTR "$RESULT" "C"
advertise "HAS_CVMFS_IGWN_CONTAINERS" "$RESULT" "C"


info "Checking for IGWN FRAMES availability"

HAS_SINGULARITY=`get_glidein_config_value HAS_SINGULARITY`
FS=ligo.osgstorage.org
FS_ATTR="HAS_LIGO_FRAMES"
RESULT="False"
TEST_FILE=`shuf -n 1 client/frame_files_small.txt`
OSG_SINGULARITY_PATH=`get_glidein_config_value OSG_SINGULARITY_PATH`
OSG_SINGULARITY_EXTRA_OPTS=`get_glidein_config_value OSG_SINGULARITY_EXTRA_OPTS`
OSG_SINGULARITY_IMAGE_DEFAULT=`get_glidein_config_value OSG_SINGULARITY_IMAGE_DEFAULT`
TEST_CMD="head -c 1k $TEST_FILE"

if [ "x$HAS_SINGULARITY" = "xTrue" ]; then
    info "Testing LIGO frames inside singularity"
    info "Making copy of $X509_USER_PROXY"
    cp $X509_USER_PROXY $PWD/frames_test_proxy
    chmod 600 $PWD/frames_test_proxy
    info "export SINGULARITYENV_X509_USER_PROXY=/srv/frames_test_proxy;setsid $OSG_SINGULARITY_PATH exec --bind $PWD:/srv $OSG_SINGULARITY_EXTRA_OPTS $OSG_SINGULARITY_IMAGE_DEFAULT $TEST_CMD | grep Frame"
    if ! (export SINGULARITYENV_X509_USER_PROXY=/srv/frames_test_proxy;setsid $OSG_SINGULARITY_PATH exec --bind $PWD:/srv \
                                            $OSG_SINGULARITY_EXTRA_OPTS \
                                            "$OSG_SINGULARITY_IMAGE_DEFAULT" \
                                            $TEST_CMD \
                                            | grep Frame) 1>&2 \
    ; then
        RESULT="False"
    else
        RESULT="True"
    fi
else
    if ! (setsid  $TEST_CMD | grep Frame) 1>&2 \
    ; then
        RESULT="False"
    else
        RESULT="True"
    fi
fi
advertise $FS_ATTR "$RESULT" "C"
advertise "HAS_CVMFS_IGWN_PRIVATE_DATA" "$RESULT" "C"
advertise "HAS_CVMFS_LIGO_STORAGE" "$RESULT" "C"
advertise "HAS_CVMFS_IGWN_STORAGE" "$RESULT" "C"
##################                                                                                                                                                   
info "All done - time to do some real work!"
