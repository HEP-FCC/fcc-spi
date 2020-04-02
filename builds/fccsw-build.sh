#!/usr/bin/env bash

set -x

#---Create stampfile to enable our jenkins to purge old builds------------------------------
touch $WORKSPACE/controlfile

#---Set up environment----------------------------------------------------------------------
cd $WORKSPACE/fccsw
source $WORKSPACE/fccsw/init.sh
env | sort

#---Exit immediately after non-zero return code---------------------------------------------
set -e

#---Clean build folder----------------------------------------------------------------------
make purge

#---Run build-------------------------------------------------------------------------------
ctest -V -S $WORKSPACE/fcc-spi/builds/fccsw-build.cmake
