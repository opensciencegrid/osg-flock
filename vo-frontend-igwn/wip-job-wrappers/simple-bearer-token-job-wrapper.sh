#!/bin/bash
[[ -n $BEARER_TOKEN_FILE ]] || export BEARER_TOKEN_FILE="$_CONDOR_CREDS/ligo.use"
exec "$@"
