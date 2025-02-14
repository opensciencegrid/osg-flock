#!/bin/bash

# creates a fake glide_XXXX setup and tests the garbage collection tool

set -e

# Test 1 - make sure the right number of directories get removed

echo
rm -rf test
mkdir test
cd test

# fake older dirs
mkdir glide_Sk31 \
    && touch -d "2 days ago" glide_Sk31 
mkdir glide_zjf1d \
    && touch -d "15 days ago" glide_zjf1d 
mkdir glide_5skx \
    && touch -d "2 days ago" glide_5skx \
    && touch -d "1 days ago" glide_5skx/_GLIDE_LEASE_FILE
mkdir glide_06ek \
    && touch -d "2 days ago" glide_06ek \
    && touch -d "10 minutes ago" glide_06ek/_GLIDE_LEASE_FILE
mkdir some_other_dir \
    && touch -d "15 days ago" some_other_dir \
    && mkdir some_other_dir/do-not-visit-this-dir

# my own dir
mkdir glide_3jz4 \
    && mkdir glide_3jz4/client_group_main \
    && cp ../garbage_collection* glide_3jz4/client_group_main/

# now run the test
cd glide_3jz4
echo "GLIDEIN_WORKSPACE_ORIG $PWD" >glidein_config
echo "CONDOR_VARS_FILE $PWD/condor_vars" >>glidein_config
echo "GLIDEIN_Entry_Name OSG_US_ISI_osg" >>glidein_config
cd client_group_main
./garbage_collection $PWD/../glidein_config
cd ..

echo
echo "GWMS glidein_config:"
cat glidein_config

echo
echo "GWMS condor_vars:"
cat condor_vars

cd ..
COUNT=$(ls | wc -l)
if [ $COUNT -ne 4 ]; then
    echo "ERROR: Incorrect number of directories remaining"
    exit 1
fi
cd ..

# Test 2 - 10 glide dirs we can't move

echo
rm -rf test
mkdir test
cd test

for I in $(seq 10); do
    mkdir glide_$I \
        && touch -d "15 days ago" glide_$I \
        && chmod 500 glide_$I
done

# my own dir
mkdir glide_3jz4 \
    && mkdir glide_3jz4/client_group_main \
    && cp ../garbage_collection* glide_3jz4/client_group_main/

# now run the test
cd glide_3jz4
echo "GLIDEIN_WORKSPACE_ORIG $PWD" >glidein_config
echo "CONDOR_VARS_FILE $PWD/condor_vars" >>glidein_config
echo "GLIDEIN_Entry_Name OSG_US_ISI_osg" >>glidein_config
cd client_group_main
./garbage_collection $PWD/../glidein_config
cd ..

echo
echo "GWMS glidein_config:"
cat glidein_config

echo
echo "GWMS condor_vars:"
cat condor_vars

cd ../../
rm -rf test

echo
echo "All tests passed."

