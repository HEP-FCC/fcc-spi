#!/bin/sh

# Create controlfile
touch controlfile
export LCG_VERSION=$1

if [ ! -z $2 ]; then
  export FCC_VERSION=$2
else
  export FCC_VERSION=stable
fi

THIS=$(dirname ${BASH_SOURCE[0]})

# Detect platform
TOOLSPATH=/cvmfs/fcc.cern.ch/contrib/tools/
if [[ $BUILDTYPE == *Release* ]]; then
  export PLATFORM=`python $TOOLSPATH/hsf_get_platform.py --compiler $COMPILER --buildtype opt`
else
  export PLATFORM=`python $TOOLSPATH/hsf_get_platform.py --compiler $COMPILER --buildtype dbg`
fi

if [[ $PLATFORM = *gcc73* ]]; then
  export PLATFORM=${PLATFORM//gcc73/gcc7}
fi

# Detect os
OS=`python $TOOLSPATH/hsf_get_platform.py --get os`

# Detect day if not set
if [[ -z ${weekday+x} ]]; then
  export weekday=`date +%a`
fi

# Clone spack repo
SPACKDIR=$WORKSPACE/spack

if [ ! -d $SPACKDIR ]; then
  git clone https://github.com/HEP-FCC/spack.git $SPACKDIR
fi
export SPACK_ROOT=$SPACKDIR

# Setup new spack home
export SPACK_HOME=$WORKSPACE
export HOME=$SPACK_HOME
export SPACK_CONFIG=$HOME/.spack

# Source environment
source $SPACK_ROOT/share/spack/setup-env.sh

# Add new repo hep-spack
export HEP_REPO=$SPACK_ROOT/var/spack/repos/hep-spack
if [ ! -d $HEP_REPO ]; then
  git clone https://github.com/HEP-SF/hep-spack.git $HEP_REPO
fi
spack repo add $HEP_REPO

# Add new repo fcc-spack
export FCC_REPO=$SPACK_ROOT/var/spack/repos/fcc-spack
if [ ! -d $FCC_REPO ]; then
  git clone https://github.com/HEP-FCC/fcc-spack.git $FCC_REPO
fi
spack repo add $FCC_REPO

# Create packages
source $THIS/create_packages.sh

# Overwrite packages configuration
mv $WORKSPACE/packages.yaml $SPACK_CONFIG/linux/packages.yaml

# Set up compiler
# Default values
gcc49version=4.9.3
gcc62version=6.2.0
gcc73version=7.3.0
gcc8version=8.3.0
export COMPILERversion=${COMPILER}version

# gcc8 is an abstraction of the full versio (8.2.0, 8.3.0, ...), hence it can point
# to different specific version of gcc-8.X.X
lcg_compiler_version=`cat lcg_compiler.txt`
IFS='.' read -ra lcg_compiler_version <<< "$lcg_compiler"
COMPILER_TWO_DIGITS="${lcg_compiler_version[0]}${lcg_compiler_version[1]}"

if [ $COMPILER_TWO_DIGITS == "82" ]; then
    gcc8version=8.2.0
fi

# Prepare defaults/linux configuration files (compilers and external packages)
cat $THIS/config/compiler-${OS}-gcc${COMPILER_TWO_DIGITS}.yaml > $SPACK_CONFIG/linux/compilers.yaml
cat $THIS/config/config.yaml > $SPACK_CONFIG/config.yaml

# Use a default compiler taken from cvmfs/sft.cern.ch
source /cvmfs/sft.cern.ch/lcg/contrib/gcc/${!COMPILERversion}binutils/x86_64-${OS}/setup.sh

# Find tbb lib
tbb_lib="$(cat .spack/linux/packages.yaml | grep intel-tbb@ | tr -s " " | cut -d" " -f5 | tr -d "}" )/lib"
# Find root lib
root_lib="$(cat .spack/linux/packages.yaml | grep root@ | tr -s " " | cut -d" " -f5 | tr -d "}" )/lib"

EXTRA_LIBS="${tbb_lib}:${root_lib}"
sed -i "s#EXTRA_LIBS#`echo $EXTRA_LIBS`#" $SPACK_CONFIG/linux/compilers.yaml

# TEMP Remove tbb from hep-spack
rm -rf $HEP_REPO/packages/tbb
