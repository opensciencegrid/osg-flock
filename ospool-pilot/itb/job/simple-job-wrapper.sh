#!/bin/sh
# ^^^^^^^ Make sure this script is strict POSIX sh as that is what GWMS wants

# OSPool: set up TMPDIR to be in the job dir; try to avoid /tmp at
# sites as some users tend to fill it up and disrupt the host.
#
# This is not done when inside Singularity as the equivalent is accomplished
# via bind mounts.
if [ "x$_CONDOR_SCRATCH_DIR" != "x" ]; then
    TMPDIR="$_CONDOR_SCRATCH_DIR/.local-tmp"
else
    TMPDIR=$(pwd)"/.local-tmp"
fi
export TMPDIR
OSG_WN_TMP=$TMPDIR
export OSG_WN_TMP
mkdir -p $TMPDIR

# Always make sure we have a reasonable PATH if it is not otherwise set.
# Should be valid both inside and outside the container.
if [ "x$PATH" = "x" ]; then
    PATH="/usr/local/bin:/usr/bin:/bin"
fi
export PATH

# GlideinWMS utility files and libraries - particularly condor_chirp
if [ -d "$PWD/.gwms.d/bin" ]; then
    # This includes the portable Python only condor_chirp
    PATH="$PWD/$GWMS_SUBDIR/bin:$PATH"
    export PATH
fi

# Some java programs have seen problems with the timezone in our containers.
# If not already set, provide a default TZ
if [ "x$TZ" = "x" ]; then
    TZ="UTC"
    export TZ
fi

exec "$@"
