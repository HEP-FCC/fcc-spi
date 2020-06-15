#!/usr/bin/env bash

set -x

#---Create stampfile to enable our jenkins to purge old builds------------------------------
touch $WORKSPACE/controlfile

#---Set up environment----------------------------------------------------------------------
cd $WORKSPACE/fccsw
source init.sh
make -j `getconf _NPROCESSORS_ONLN`
make -j `getconf _NPROCESSORS_ONLN` test
