#!/bin/bash

function run_test {
    
    # cleanup
    rm -f .singularity*
    rm -f test.err test.out

    echo "Running" "$@"
    "$@" >test.out 2>test.err
    if [ $? -eq 0 ]; then
        echo "OK"
        rm -f test.err test.out
        return 0
    else
        cat test.err test.out
        echo "ERROR"
        exit 1
    fi
}

function test_basic {
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.non-singularity
    if ! ($PWD/user-job-wrapper.sh ls); then
        echo "ERROR: job exited non-zero"
        return 1
    fi
    if [ -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok exists - this is unexpected"
        return 1 
    fi
    return 0
}

function test_fail {
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.non-singularity
    if ($PWD/user-job-wrapper.sh false); then
        echo "ERROR: job exited zero - we expected failure"
        return 1
    fi
    return 0
}

# we need a copy as it will be used inside containers
cp ../itb-user-job-wrapper.sh ./user-job-wrapper.sh

export GWMS_DEBUG=1

# run the tests
run_test test_basic
run_test test_fail

# cleanup
rm -f .singularity.startup-ok .user-job-wrapper.sh user-job-wrapper.sh


