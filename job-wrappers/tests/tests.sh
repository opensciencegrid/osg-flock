#!/bin/bash

function run_test {
    
    # cleanup
    rm -rf .singularity-cache >/dev/null 2>&1
    rm -r .singularity* >/dev/null 2>&1
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

function test_non_singularity {
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

function test_non_singularity_fail {
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.non-singularity
    if ($PWD/user-job-wrapper.sh false); then
        echo "ERROR: job exited zero - we expected failure"
        return 1
    fi
    return 0
}

function test_singularity {
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity
    if ! ($PWD/user-job-wrapper.sh ls); then
        echo "ERROR: job exited non-zero"
        return 1
    fi
    if [ ! -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok is missing - did the job run in Singularity?"
        return 1 
    fi
    return 0
}

function test_singularity_docker_direct {
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity-docker-direct
    if ! ($PWD/user-job-wrapper.sh ls); then
        echo "ERROR: job exited non-zero"
        return 1
    fi
    if [ ! -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok is missing - did the job run in Singularity?"
        return 1 
    fi
    return 0
}

function test_singularity_clean_env {
    rm -f out.txt
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity
    export _CONDOR_JOB_AD=$PWD/.job_ad.clean-env
    if ! (GLIDEIN_Client=submit.ligo.org _CONDOR_ANCESTOR_123=ping FOO=hello BAR=world FOOBAR=DO_NOT_PROPAGATE $PWD/user-job-wrapper.sh env | sort >out.txt 2>&1); then
        echo "ERROR: job exited non-zero"
        return 1
    fi
    if [ ! -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok is missing - did the job run in Singularity?"
        return 1 
    fi
    if (grep FOOBAR out.txt >/dev/null); then
        echo "ERROR: FOOBAR envvar propagated?"
        return 1 
    fi
    rm -f out.txt
    return 0
}

function test_singularity_clean_env_2 {
    rm -f out.txt
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity
    export _CONDOR_JOB_AD=$PWD/.job_ad.clean-env
    if ! (. /cvmfs/oasis.opensciencegrid.org/osg/sw/module-init.sh && FOOBAR=DO_NOT_PROPAGATE $PWD/user-job-wrapper.sh env | sort >out.txt 2>&1); then
        echo "ERROR: job exited non-zero"
        return 1
    fi
    if [ ! -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok is missing - did the job run in Singularity?"
        return 1 
    fi
    if (grep FOOBAR out.txt >/dev/null); then
        echo "ERROR: FOOBAR envvar propagated?"
        return 1 
    fi
    rm -f out.txt
    return 0
}

function test_singularity_ld_library_path {
    rm -f out.txt
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity
    if ! (LD_LIBRARY_PATH=DO_NOT_PROPAGATE $PWD/user-job-wrapper.sh env >out.txt 2>/dev/null); then
        echo "ERROR: job exited non-zero"
        return 1
    fi
    if [ ! -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok is missing - did the job run in Singularity?"
        return 1 
    fi
    if (grep DO_NOT_PROPAGATE out.txt >/dev/null); then
        cat out.txt
        echo "ERROR: LD_LIBRARY_PATH propagated?"
        return 1 
    fi
    rm -f out.txt
    return 0
}

function test_singularity_fail_1 {
    # missing image
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity-fail
    $PWD/user-job-wrapper.sh ls
    if [ -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok exists - this is unexpected"
        return 1 
    fi
    return 0
}

function test_singularity_fail_2 {
    # test with good image, bad Singularity binary
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity-bad-detection
    export _CONDOR_WRAPPER_ERROR_FILE=$PWD/.condor_wrapper_error_file
    rm -f $_CONDOR_WRAPPER_ERROR_FILE
    if ($PWD/user-job-wrapper.sh true); then
        echo "ERROR: job exited zero, we expected non-zero"
        return 1
    fi
    if [ -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok exists - this is unexpected"
        return 1 
    fi
    if [ ! -e $_CONDOR_WRAPPER_ERROR_FILE ]; then
        echo "ERROR: \$_CONDOR_WRAPPER_ERROR_FILE was not created"
        return 1 
    fi
    rm -f $_CONDOR_WRAPPER_ERROR_FILE
    return 0
}

function test_singularity_fail_3 {
    # test with good image, bad user job
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity
    if ($PWD/user-job-wrapper.sh false); then
        echo "ERROR: job exited zero, we expected non-zero"
        return 1
    fi
    if [ ! -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok is missing - this is unexpected"
        return 1 
    fi
    return 0
}

function test_singularity_gpu_cuda {
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity-gpu-cuda
    if ! ($PWD/user-job-wrapper.sh /usr/bin/nvidia-smi); then
        echo "ERROR: job exited non-zero"
        return 1
    fi
    if [ ! -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok is missing - did the job run in Singularity?"
        return 1 
    fi
    return 0
}

function test_singularity_gpu_tensorflow {
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity-gpu-tensorflow
    if ! ($PWD/user-job-wrapper.sh /usr/bin/nvidia-smi); then
        echo "ERROR: job exited non-zero"
        return 1
    fi
    if [ ! -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok is missing - did the job run in Singularity?"
        return 1 
    fi
    return 0
}

function test_singularity_gpu_rift {
    export _CONDOR_MACHINE_AD=$PWD/.machine_ad.singularity-gpu-rift
    if ! ($PWD/user-job-wrapper.sh /usr/bin/nvidia-smi); then
        echo "ERROR: job exited non-zero"
        return 1
    fi
    if [ ! -e .singularity.startup-ok ]; then
        echo "ERROR: .singularity.startup-ok is missing - did the job run in Singularity?"
        return 1 
    fi
    return 0
}

# we need a copy as it will be used inside containers
cp ../user-job-wrapper.sh .

export GWMS_DEBUG=1

# run the tests
run_test test_non_singularity
run_test test_singularity_clean_env
run_test test_singularity_clean_env_2
run_test test_singularity_ld_library_path
run_test test_non_singularity_fail
run_test test_singularity
#run_test test_singularity_docker_direct
run_test test_singularity_fail_1
run_test test_singularity_fail_2
run_test test_singularity_fail_3

# only run on GPU host, for example ldas-pcdev3.ligo.caltech.edu
if nvidia-smi >/dev/null 2>&1; then
    run_test test_singularity_gpu_cuda
    run_test test_singularity_gpu_tensorflow
    run_test test_singularity_gpu_rift
else
    echo "Skipping GPU tests as nvidia-smi can not be found"
fi

# cleanup
rm -f .singularity.startup-ok .user-job-wrapper.sh user-job-wrapper.sh


