#!/bin/bash

#############################################################################
##
##  limit the memory a user job can use
##  see: https://ticket.grid.iu.edu/goc/16927
##  added by rynge 12/2/13
##

ulimit -d 2000000 2>/dev/null || /bin/true

# testing this - not sure if it works as intended
ulimit -v 3000000 2>/dev/null || /bin/true

