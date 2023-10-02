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
        add_condor_vars_line $key "$atype" "-" "+" "Y" "Y" "-"
    fi

    if [ "$atype" = "S" ]; then
        echo "$key = \"$value\""
    else
        echo "$key = $value"
    fi
}

if [ "x$glidein_config" = "x" ]; then
    glidein_config="NONE"
    info "No arguments provided - assuming HTCondor startd cron mode"
else
    info "Arguments to the script: $@"
fi

if [ "$glidein_config" != "NONE" ]; then
    # import advertise and add_condor_vars_line functions
    add_config_line_source=`grep '^ADD_CONFIG_LINE_SOURCE ' $glidein_config | awk '{print $2}'`
    source $add_config_line_source

    condor_vars_file=`grep -i "^CONDOR_VARS_FILE " $glidein_config | awk '{print $2}'`
fi

##################

info "Checking for IGWN FRAMES availability..."
info "Current X509_USER_PROXY=${X509_USER_PROXY}"

FS_ATTR="HAS_IGWN_FRAMES"
TEST_FILE_LIST="client/ligo-cvmfs-data.txt"

# test all GWF files in the file
OVERALL_RESULT="True"  # start with success and assert otherwise
while read CVMFS_ATTR GWF \
; do
    TEST_CMD="head -c4 $GWF"
    if ! (setsid $TEST_CMD | grep IGWD) 1>&2; then
        RESULT="False"
        OVERALL_RESULT="${RESULT}"
        warn "Could not read $GWF"
    else
        RESULT="True"
        info "Successfully read $GWF"
    fi
    advertise "${CVMFS_ATTR}" "${RESULT}" "C"
done <${TEST_FILE_LIST}

advertise $FS_ATTR "$OVERALL_RESULT" "C"
advertise "HAS_LIGO_FRAMES" "$OVERALL_RESULT" "C"
advertise "HAS_CVMFS_IGWN_PRIVATE_DATA" "$OVERALL_RESULT" "C"
advertise "HAS_CVMFS_IGWN_STORAGE" "$OVERALL_RESULT" "C"

info "Done."
