#!/bin/sh

# Import some common functions
source common-functions.sh

env | sort

echo "export COMPILER=$COMPILER" >> $WORKSPACE/setup.sh
echo "export BUILDTYPE=$BUILDTYPE" >> $WORKSPACE/setup.sh

BUILDMODE="nightly"
pkgname="fccdevel"

# Prepare environment
echo "export WORKSPACE=$PWD" >> $WORKSPACE/setup.sh
echo "export weekday=$weekday" >> $WORKSPACE/setup.sh
echo "source fcc-spi/jk-setup-spack.sh ${LCG_VERSION} ${FCC_VERSION}" >> $WORKSPACE/setup.sh

source fcc-spi/jk-setup-spack.sh ${LCG_VERSION} ${FCC_VERSION}
fccspi_check_error $? "Prepare environment and local setup"

# Setup CDash options to report build results
CDASH_UPLOAD_URL=http://cdash.cern.ch/submit.php?project=FCC
CDASH_TRACK=Externals

# Install the FCC software stack
echo "Installing $pkgname:"
echo "spack install --cdash-upload-url=$CDASH_UPLOAD_URL --cdash-track=$CDASH_TRACK $pkgname %gcc@${!COMPILERversion}"
spack install --cdash-upload-url=$CDASH_UPLOAD_URL --cdash-track=$CDASH_TRACK $pkgname %gcc@${!COMPILERversion}
fccspi_check_error $? "spack install"

# Get hash of installed package
pkghash=`spack find -L ${pkgname}%gcc@${!COMPILERversion}  | grep $pkgname | cut -d" " -f 1`

if [ "$CVMFS_INSTALL" == true ]; then

  echo "$tempdir"

  # Create buildcache
  spack install patchelf %gcc@${!COMPILERversion}
  fccspi_check_error $? "install patchelf"

  spack buildcache create -d $WORKSPACE/tarballs -u -a $pkgname
  fccspi_check_error $? "create binary for $pkgname"

  spack buildcache create -d $WORKSPACE/tarballs -u patchelf
  fccspi_check_error $? "create binary for patchelf"

  # Define path to get the buildcache
  export BUILDCACHE_PATH=$WORKSPACE/tarballs

  # Define path to send the buildcache in the cvmfs node
  export BUILDCACHETARGET=/var/spool/cvmfs/fcc.cern.ch/sftnight/build_cache

  # Send packages to the cvmfs stratum 0 node
  kinit sftnight@CERN.CH -5 -V -k -t /ec/conf/sftnight.keytab
  scp -r $BUILDCACHE_PATH sftnight@cvmfs-fcc:$BUILDCACHETARGET
  fccspi_check_error $? "Send binaries remotely to the CVMFS stratum 0 node"

  export BUILDCACHETARGET=$BUILDCACHETARGET/tarballs
  export PKGHASH=${pkghash}
  export LCG_VERSION=${LCG_VERSION}

#--Create property file to transfer variables
cat > $WORKSPACE/properties.txt << EOF
PLATFORM=${PLATFORM}
COMPILER=${COMPILER}
weekday=${weekday}
BUILDCACHE=${BUILDCACHETARGET}
PKGHASH=${pkghash}
PKGNAME=${pkgname}
LCG_VERSION=${LCG_VERSION}
FCC_VERSION=${FCC_VERSION}
BUILDTYPE=${BUILDTYPE}
BUILDMODE=${BUILDMODE}
EOF

fi

# Print summary of install packages after some newlines
python -c 'print "\n"*5'
python -c 'print "="*80'
spack find -p | sed "s@/.*`echo $PWD`@<prefix>@"
echo ""
echo "Local <prefix>: $PWD"
python -c 'print "="*80'
python -c 'print "\n"*5'
