#!/bin/bash

#############################################################################
#
#  Trace callback
#

if [ ! -e ../../trace-callback ]; then
    (wget -nv -O ../../trace-callback http://obelix.isi.edu/osg/agent/trace-callback && chmod 755 ../../trace-callback) >/dev/null 2>&1 || /bin/true
fi
../../trace-callback start >.trace-callback.log 2>&1 || /bin/true


