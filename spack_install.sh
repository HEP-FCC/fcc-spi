#!/bin/sh

set -x

usage()
{
    if [[ -n "$1" ]]; then
       echo "unexpected parameter: $1"
    fi
    echo "usage: spack_install.sh [options] [-h]"
}

# Dont cleanup by default
cleanup=false

# Parsing arguments
while [ "$1" != "" ]; do
    case $1 in
        -p | --prefix )         shift
                                prefix=$1
                                ;;
        -b | --buildcache )     shift
                                buildcache=$1
                                ;;
        -c | --compiler )       shift
                                compiler=$1
                                ;;
        --package )             shift
                                package=$1
                                ;;
        --pkghash )             shift
                                pkghash=$1
                                ;;
        -v | --viewpath )       shift
                                viewpath=$1
                                ;;
        -l | --lcgversion )     shift
                                lcgversion=$1
                                ;;
        --platform )            shift
                                platform=$1
                                ;;
        --branch )              shift
                                branch=$1
                                ;;
        --clean )               cleanup=true
                                ;;
        --weekday )              shift
                                weekday=$1
                                ;;
        --spack-tag )           shift
                                spacktag=$1
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage $1
                                exit 1
    esac
    shift
done

check_error()
{
    local last_exit_code=$1
    local last_cmd=$2
    if [[ ${last_exit_code} -ne 0 ]]; then
        echo "${last_cmd} exited with code ${last_exit_code}"
        echo "TERMINATING JOB"
        exit 1
    else
        echo "${last_cmd} completed successfully"
    fi
}

update_latest(){
  package=$1
  lcgversion=$2

  if [[ "$package" == "fccsw" ]]; then
    installation="fccsw"
  else
    installation="externals"
  fi

  if [[ $prefix == *releases* ]]; then
    # Releases
    buildtype="releases"
  else
    buildtype="nightlies"
  fi

  FROM=/cvmfs/fcc.cern.ch/sw/views/$buildtype/$installation/latest
  TO=$viewpath

  ln -sf $TO $FROM
}

create_user_friendly_access(){
  pkghash=$1
  from=$2

  full_path=`spack find -p /${pkghash} | tail -n 1 | awk  '{print $2}'`

  TO=$full_path
  FROM=$from

  mkdir -p `dirname $FROM`
  # Create link to $TO path from $FROM
  # $FROM (new path) points to $TO (existing path)
  ln -sf $TO $FROM
  check_error $? "Creating link from: $FROM --> to: $TO"
}



# Create controlfile
touch controlfile
THIS=$(dirname ${BASH_SOURCE[0]})

if [ "$TMPDIR" == "" ]; then
  TMPDIR=$HOME/spackinstall
  mkdir -p $TMPDIR
fi
echo "Temporary directory: $TMPDIR"

# Clean previous .spack configuration if exists
rm -rf $TMPDIR/.spack

# Identify buildtype (Release or nightly)
if [[ $prefix == *releases* ]]; then
  # Releases
  buildtype="releases"
  EOS_BUILDCACHE_PATH=/eos/project/f/fccsw-web/www/binaries/releases
else
  buildtype="nightlies"
  EOS_BUILDCACHE_PATH=/eos/project/f/fccsw-web/www/binaries/nightlies
fi

# split original platform string into array using '-' as a separator
# example: x86_64-slc6-gcc62-opt
TARGET_PLATFORM="$platform"

IFS=- read -ra PART <<< "$platform"
TARGET_ARCH="${PART[0]}"
TARGET_OS="${PART[1]}"
TARGET_COMPILER="${PART[2]}"
TARGET_MODE="${PART[3]}"

echo "Target Platform information"
echo "Architecture: $TARGET_ARCH"
echo "Operating System: $TARGET_OS"
echo "Compiler: $TARGET_COMPILER"
echo "Mode: $TARGET_MODE"

# Detect host platform
# Need to use a compiler compatible with the Operating system where the job is
# running, even if the set of packages to be installed were built on a different
# platform.
TOOLSPATH=/cvmfs/fcc.cern.ch/sw/0.8.3/tools/
if [[ $TARGET_MODE == *opt* ]]; then
  export PLATFORM=`python $TOOLSPATH/hsf_get_platform.py --compiler $TARGET_COMPILER --buildtype opt`
else
  export PLATFORM=`python $TOOLSPATH/hsf_get_platform.py --compiler $TARGET_COMPILER --buildtype dbg`
fi

#if [[ $PLATFORM != $platform ]]; then
#  echo "Replacing platform, from: $platform, to: $PLATFORM"
#  platform=$PLATFORM
#fi

# assign new platform values
IFS=- read -ra PART <<< "$platform"
ARCH="${PART[0]}"
OS="${PART[1]}"
PLATFORMCOMPILER="${PART[2]}"
MODE="${PART[3]}"

echo "Host Platform information (where this job is running)"
echo "Architecture: $ARCH"
echo "Operating System: $OS"
echo "Compiler: $PLATFORMCOMPILER"
echo "Mode: $MODE"

# Clone spack repo

# Use develop if there is no tags specified (use tags to reproduce releases)
if [[ "$spacktag" == "" ]]; then
   spacktag="develop"
fi

if [[ -d $TMPDIR/spack ]]; then
   echo "Removing existing $TMPDIR/spack directory"
   rm -rf $TMPDIR/spack
   check_error $? "Remove existing $TMPDIR/spack directory"
fi

echo "Cloning spack repo"
echo "git clone https://github.com/HEP-FCC/spack.git -b $spacktag $TMPDIR/spack"
git clone https://github.com/HEP-FCC/spack.git -b $spacktag $TMPDIR/spack
check_error $? "cloning spack repo from branch/tag: $spacktag"
export SPACK_ROOT=$TMPDIR/spack

# Setup new spack home
export SPACK_HOME=$TMPDIR
export HOME=$SPACK_HOME
export SPACK_CONFIG=$HOME/.spack

# Source environment
echo "Preparing spack environment"
source $SPACK_ROOT/share/spack/setup-env.sh

# Add new repo hep-spack
echo "Cloning hep-spack repo"
echo "git clone https://github.com/HEP-SF/hep-spack.git $SPACK_ROOT/var/spack/repos/hep-spack"
git clone https://github.com/HEP-SF/hep-spack.git $SPACK_ROOT/var/spack/repos/hep-spack
spack repo add $SPACK_ROOT/var/spack/repos/hep-spack
export FCC_SPACK=$SPACK_ROOT/var/spack/repos/fcc-spack

# Check fcc-spack branch is not empty
if [[ -z "$branch" ]]; then
  echo "Error: Branch not defined for the fcc-spack repo ($branch)"
  exit 1
fi

# Add new repo fcc-spack
echo "Cloning fcc-spack repo"
echo "git clone https://github.com/HEP-FCC/fcc-spack.git - $branch SPACK_ROOT/var/spack/repos/fcc-spack"
git clone https://github.com/HEP-FCC/fcc-spack.git -b $branch $SPACK_ROOT/var/spack/repos/fcc-spack
spack repo add $SPACK_ROOT/var/spack/repos/fcc-spack
export HEP_SPACK=$SPACK_ROOT/var/spack/repos/hep-spack

# Get compiler from LCG_externals
if [[ $lcgversion == LCG_* ]]; then
  LCG_externals="/cvmfs/sft.cern.ch/lcg/releases/$lcgversion/LCG_*_${TARGET_ARCH}-${TARGET_OS}-${TARGET_COMPILER}-*.txt"
else
  LCG_externals="/cvmfs/sft.cern.ch/lcg/nightlies/$lcgversion/$weekday/LCG_*_${PLATFORM}.txt"
fi

# Set up compiler
python $THIS/get_compiler.py $LCG_externals
lcg_compiler=`cat lcg_compiler.txt`

# Set up compiler
# Default values
gcc49version=4.9.3
gcc62version=6.2.0
gcc73version=7.3.0
gcc8version=8.3.0

# gcc8 is an abstraction of the full versio (8.2.0, 8.3.0, ...), hence it can point
# to different specific version of gcc-8.X.X
lcg_compiler_version=`cat lcg_compiler.txt`
IFS='.' read -ra lcg_compiler_version <<< "$lcg_compiler"
COMPILER_TWO_DIGITS="${lcg_compiler_version[0]}${lcg_compiler_version[1]}"

if [ $COMPILER_TWO_DIGITS == "82" ]; then
    gcc8version=8.2.0
fi

if [[ "$PLATFORMCOMPILER" != "$compiler"  ]]; then
   echo "ERROR: Platform compiler (${PLATFORMCOMPILER}) and selected compiler (${compiler}) do not match"
   exit 1
fi

export compilerversion=${compiler}version

# Prepare defaults/linux configuration files (compilers and external packages)
# Add compiler compatible with the host platform
cat $THIS/config/compiler-${OS}-gcc${COMPILER_TWO_DIGITS}.yaml > $SPACK_CONFIG/linux/compilers.yaml

# Add compiler compatible with the target platform (without head line)
if [[ "$OS-$PLATFORMCOMPILER" != "$TARGET_OS-$TARGET_COMPILER" ]]; then
  cat $THIS/config/compiler-${TARGET_OS}-gcc${COMPILER_TWO_DIGITS}.yaml | tail -n +2 >> $SPACK_CONFIG/linux/compilers.yaml
fi

cat $THIS/config/config.yaml > $SPACK_CONFIG/config.yaml

# Use a default patchelf installed in fcc.cern.ch
# spack buildcache tries to install it if it is not found
#sed "s@{{COMPILER}}@`echo ${!compilerversion}`@"  $THIS/config/patchelf.yaml >> $SPACK_CONFIG/linux/packages.yaml

# Use a default compiler taken from cvmfs/sft.cern.ch
source /cvmfs/sft.cern.ch/lcg/contrib/gcc/${!compilerversion}binutils/x86_64-${OS}/setup.sh

# Create mirrors.yaml to use external buildcache locate in EOS
spack mirror add eos_buildcache $EOS_BUILDCACHE_PATH

echo "Mirror configuration:"
spack mirror list
spack buildcache keys

if [[ "$package" == "fccswSKIPTHIS" ]]; then
  # Configure upstream installation in cvmfs
  cp $THIS/config/upstreams.tpl $SPACK_CONFIG/upstreams.yaml

  # Get FCC-externals version
  IFS=/ read -ra PART <<< "$viewpath"

  # Negative indexes are not supported in the cvmfs node
  # so we use positive indexes
  len=${#PART[@]}
  idx_version=$((len - 2))
  EXTERNALS_VERSION=${PART[$idx_version]}

  # Replace externals path
  externals=/cvmfs/fcc.cern.ch/sw/releases/externals/$EXTERNALS_VERSION/$TARGET_PLATFORM
  sed -i "s@{{EXTERNALS_PATH}}@`echo $externals`@" $SPACK_CONFIG/upstreams.yaml

  echo "Upstreams configuration:"
  cat $SPACK_CONFIG/upstreams.yaml
  echo
  echo "Available packages:"
  spack find -p
  echo

  # Execute a first look at the buildcache to load remote files
  spack buildcache list -L > /dev/null
  # Modify viewpath with the fccsw version
  fcc_version=`spack buildcache list -L | grep $pkghash | cut -d"@" -f2`
  user_prefix=${prefix/$EXTERNALS_VERSION/$fcc_version}

  # Remove last 2 components of the path (version and platform)
  prefix=`echo $prefix | rev | cut -d'/' -f3- | rev`

  # Spack requires some specific install path scheme for its internal relocation
  # but we want to find packages in easy locations for users such as:
  # /cvmfs/fcc.cern.ch/sw/releases/fccsw/<version>/<platform>
  # Therefore we will install in:
  # /cvmfs/fcc.cern.ch/sw/releases/fccsw: using the internal spack layout
  # and link to the user friendly path
  echo "New spack prefix for fccsw: $prefix"
  echo "Users will find the package on: $user_prefix"
fi

# Create config.yaml to define new prefix
if [ "$prefix" != "" ]; then
  cp $THIS/config/config.tpl $SPACK_CONFIG/linux/config.yaml
  sed -i "s#{{PREFIX_PATH}}#`echo $prefix`#" $SPACK_CONFIG/linux/config.yaml
fi

# General configuration
echo "Spack Configuration: "
spack config get config

# List of known compilers
echo "Compiler Configurations:"
spack config get compilers

# First need to install patchelf for relocation
# spack buildcache install -u patchelf
# check_error $? "spack buildcache install patchelf"

# Install patchelf for later relocation
spack install --no-cache patchelf

# Install binaries from buildcache
echo "Installing $package binary"

if [[ "$package" == "fccsw" ]]; then
   spack buildcache install -u /$pkghash
   check_error $? "spack buildcache install -u ($package)/$pkghash"
else
   spack buildcache install -u -f -a /$pkghash | grep -v "==> Fetching"
   check_error $? "spack buildcache install -u -f -a ($package)/$pkghash"
fi

# Detect day if not set
if [[ -z ${weekday+x} ]]; then
  export weekday=`date +%a`
fi

if [[ "$package" == "fccsw" ]]; then
  create_user_friendly_access $pkghash $user_prefix
fi

# Create view (only for externals)
if [[ "$package" != "fccsw" ]]; then
if [[ "$viewpath" != "" && "$package" != "" ]]; then

  # Temporal until #6266 get fixed in spack
  # Avoid problems creating views
  find $prefix -type f -iname "NOTICE" | xargs rm -f
  find $prefix -type f -iname "LICENSE" | xargs rm -f

  # Check if any view already exists in the target path
  if [[ -e $viewpath ]]; then
    echo "Removing previous existing view in $viewpath"
    rm -rf $viewpath
  fi

  echo "Creating view in $viewpath"
  exceptions="py-pyyaml"

  # Exclude fccsw
  if [[ "$package" == "fccstack" ]]; then
    exceptions=$exceptions"|fccsw"
  fi

  echo "Command: spack view -d true -e $exceptions symlink -i $viewpath /$pkghash"
  spack view -d true -e "$exceptions" symlink $viewpath /$pkghash
  viewcreated=$?
  check_error $(($result + $viewcreated)) "create view"
  if [ $viewcreated -eq 0 ];then
    # Update latest link
    update_latest $package $lcgversion
    check_error $? "update latest link"
  fi
fi

# Generate setup.sh for the view
cp $THIS/config/setup.tpl $viewpath/setup.sh

# Patch to link againts custom LCG Views
if [[ $lcgversion == LCG_* ]]; then
  # Releases
  #lcg_path="/cvmfs/fcc.cern.ch/testing/lcgview/$lcgversion/$platform"
  lcg_path=/cvmfs/sft.cern.ch/lcg/views/$lcgversion/$TARGET_PLATFORM
else
  # Nightlies
  lcg_path="/cvmfs/sft.cern.ch/lcg/views/$lcgversion/$weekday/$TARGET_PLATFORM"
fi

sed -i "s@{{lcg_path}}@`echo $lcg_path`@" $viewpath/setup.sh
sed -i "s/{{PLATFORM}}/`echo $TARGET_PLATFORM`/" $viewpath/setup.sh
sed -i "s@{{viewpath}}@`echo $viewpath`@" $viewpath/setup.sh
gaudi_dir=`spack find -p gaudi | tail -n 1 | awk  '{print $2}'`
sed -i "s@{{Gaudi_DIR}}@`echo $gaudi_dir`@" $viewpath/setup.sh
check_error $? "generate setup.sh"
fi # "$package" != "fccsw"

# Replace shebang line from xenv
if test -f $viewpath/bin/xenv; then
   # The 1 option replaces the first line
   # The whole first line gets replaced by the new shebang
   # Spack uses an absolute path to the installed python because it relies on
   # rpath, however after relocating the package to cvmfs, the path is so long
   # that it fails.
   # Since we will use this software setting up the environment, we take
   # the first python found in the path
   sed -i '1 s@^.*$@#!/usr/bin/env python\n# Shebang line automatically replaced with sed to pick python from the environment@' $viewpath/bin/xenv
   check_error $? "patch shebang in $viewpath/bin/xenv"
fi

if [ "$cleanup" = true ]; then
  echo "Cleanup"
  rm -rf $TMPDIR
  echo "Removed $TMPDIR"
  rm -rf /tmp/$USER/spack-stage
  echo "Removed /tmp/$USER/spack-stage"
fi

echo "End of build"

echo "Summary of the build"
python -c 'print "\n"*5'
python -c 'print "="*80'
spack find -p 
echo ""
python -c 'print "="*80'
python -c 'print "\n"*5'
