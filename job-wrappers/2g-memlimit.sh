#!/bin/bash

#############################################################################
##
##  limit the memory a user job can use
##  see: https://ticket.grid.iu.edu/goc/16927
##  added by rynge 12/2/13
##

ulimit -d 1900000 2>/dev/null || /bin/true

# tihs does not work with Java programs
#ulimit -v 1900000 2>/dev/null || /bin/true

