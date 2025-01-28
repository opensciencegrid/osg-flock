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

# my own dir
mkdir glide_3jz4 \
    && cp ../garbage_collection* glide_3jz4/

# now run the test
cd glide_3jz4
echo "CONDOR_VARS_FILE $PWD/condor_vars" >glidein_config
./garbage_collection $PWD/glidein_config

echo
echo "GWMS glidein_config:"
cat glidein_config

echo
echo "GWMS condor_vars:"
cat condor_vars

cd ..
COUNT=$(ls | wc -l)
if [ $COUNT -ne 3 ]; then
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
    && cp ../garbage_collection* glide_3jz4/

# now run the test
cd glide_3jz4
echo "CONDOR_VARS_FILE $PWD/condor_vars" >glidein_config
./garbage_collection $PWD/glidein_config

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

