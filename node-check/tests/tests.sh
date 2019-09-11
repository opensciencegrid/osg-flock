#!/bin/bash

function run_test {

    echo "Running" "$@"
    cd $TESTS_DIR
    "$@" >test.out 2>test.err
    cd $TESTS_DIR
    if [ $? -eq 0 ]; then
        echo
        echo "========================================================="
        cat test.err test.out
        echo "========================================================="
        echo
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
    
    rm -rf work
    mkdir work
    cd work
    cp ../../osgvo-node-advertise .

    ./osgvo-node-advertise

    # TODO: how to validate the resuls
    return 0
}

function test_gwms {
    
    rm -rf work
    mkdir work
    cd work
    cp ../../osgvo-node-advertise .
    cp ../add_config_line.source .
    touch condor_vars.lst

    echo "ADD_CONFIG_LINE_SOURCE $PWD/add_config_line.source" > glidein_config
    echo "CONDOR_VARS_FILE $PWD/condor_vars.lst" >> glidein_config 

    ./osgvo-node-advertise glidein_config client

    # TODO: how to validate the resuls
    return 0
}


TESTS_DIR=`dirname $0`
TESTS_DIR=`cd $TESTS_DIR && pwd`
cd $TESTS_DIR

# run the tests
run_test test_basic
run_test test_gwms


