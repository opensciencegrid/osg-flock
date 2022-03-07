#!/bin/bash
export BEARER_TOKEN_FILE="$_CONDOR_CREDS/ligo.use"
exec "$@"
