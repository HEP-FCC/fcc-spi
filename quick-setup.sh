# This script prepares the environment and download all required packages to
# start building FCC packages with spack. It uses a set of default variables
# that can be overwritten.
#
# Usage :
#     source fcc-spi/quick-setup.sh
#

export LCG_VERSION=LCG_96b
export FCC_VERSION=develop
export COMPILER=gcc8
export BUILDTYPE=Release
export weekday=`date +%a`

current_dir=`basename $PWD`
echo "$current_dir"
if [ "$current_dir" == "fcc-spi" ]; then
    echo "Running from parent directory: "
    cd ..
    echo "$PWD"
fi
export WORKSPACE=$PWD
source fcc-spi/jk-setup-spack.sh $LCG_VERSION $FCC_VERSION
