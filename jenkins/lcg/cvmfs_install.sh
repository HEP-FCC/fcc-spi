#!/bin/bash
weekday=`date +%a`
sudo -i -u cvsft<<EOF
shopt -s nocasematch
for iterations in {1..10}
do
  if [[ "${BUILDMODE}" == "nightly" ]]; then
      cvmfs_server transaction fcc-nightlies.cern.ch
  else
      cvmfs_server transaction fcc.cern.ch
  fi
  if [ "\$?" == "1" ]; then
    if  [[ "\$iterations" == "10" ]]; then
      echo "Too many tries... "
      exit 1
    else
       echo "Transaction is already open. Going to sleep..."
       sleep 10m
    fi
  else
    break
  fi
done

echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
echo fccsw_${FCCSW_VERSION}_$PLATFORM.txt
echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

export COMPILER=${COMPILER}
export FCCSW_VERSION=${FCCSW_VERSION}
array=(${PLATFORM//-/ })
comp=`echo ${array[2]}`

echo "THIS IS THE WEEKDAY OF TODAY: ------> $weekday"


abort=0

echo "This is the value of the BUILDMODE: ---> ${BUILDMODE}"

if [[ "${BUILDMODE}" == "nightly" ]]; then
    export NIGHTLY_MODE=1
    $WORKSPACE/lcgjenkins/clean_nightlies.py ${LCG_VERSION} $PLATFORM $weekday cvmfs
    rm /cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday/isDone-$PLATFORM
    rm /cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday/isDone-unstable-$PLATFORM
    rm /cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday/LCG_externals_$PLATFORM.txt
    rm /cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday/LCG_generators_$PLATFORM.txt
    $WORKSPACE/lcgjenkins/lcginstall.py -y -u http://lcgpackages.web.cern.ch/lcgpackages/tarFiles/nightlies/${LCG_VERSION}/$weekday -r ${LCG_VERSION} -d LCG_${LCG_VERSION}_$PLATFORM.txt -p /cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday/ -e cvmfs
    if [ "\$?" == "0" ]; then
      echo "Installation script has worked, we go on"
    else
      echo "there is an error installing the packages. Let's give it a chance though ..."
    fi

    cd  /cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday/
    wget https://lcgpackages.web.cern.ch/lcgpackages/tarFiles/nightlies/${LCG_VERSION}/$weekday/isDone-$PLATFORM
    wget https://lcgpackages.web.cern.ch/lcgpackages/tarFiles/nightlies/${LCG_VERSION}/$weekday/isDone-unstable-$PLATFORM
    $WORKSPACE/lcgjenkins/extract_LCG_summary.py /cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday $PLATFORM ${LCG_VERSION} RELEASE
    if [ -f "/cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday/isDone-$PLATFORM" ] && [ xtrue = "x${VIEWS_CREATION}" ]; then
      echo "The installation of the nightly is completed with all packages, let's go for the view creation"
      $WORKSPACE/lcgcmake/cmake/scripts/create_lcg_view.py -l /cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday -p $PLATFORM -d -B /cvmfs/sft-nightlies.cern.ch/lcg/views/${LCG_VERSION}/$weekday/$PLATFORM
      rm /cvmfs/sft-nightlies.cern.ch/lcg/views/${LCG_VERSION}/latest/$PLATFORM
      cd /cvmfs/sft-nightlies.cern.ch/lcg/views/${LCG_VERSION}/latest
      ln -s ../$weekday/$PLATFORM
    elif [ -f "/cvmfs/sft-nightlies.cern.ch/lcg/nightlies/${LCG_VERSION}/$weekday/isDone-unstable-$PLATFORM" ]; then
        echo "The installation has not been completed and we do not create the view"
    fi

    cd $HOME
    cvmfs_server publish sft-nightlies.cern.ch

elif [[ "${BUILDMODE}" == "release" ]]; then
    $WORKSPACE/jenkins/lcg/lcginstall.py -u http://lcgpackages.web.cern.ch/lcgpackages/tarFiles/releases -r ${FCCSW_VERSION} -d fccsw_${FCCSW_VERSION}_$PLATFORM.txt -p /cvmfs/fcc.cern.ch/sw/releases/fccsw -e cvmfs --dry-run
    if [ "\$?" == "0" ]; then
      echo "Installation script has worked, we go on"
      abort=1
    else
      echo "there is an error installing the packages. Exiting ..."
      cd $HOME
      cvmfs_server abort -f fcc.cern.ch
      exit 1
    fi

    cd  /cvmfs/sft.cern.ch/sw/releases/fccsw/${LCG_VERSION}
    $WORKSPACE/jenkins/lcg/extract_FCC_summary.py . $PLATFORM ${FCCSW_VERSION} RELEASE
    if [ ${VIEWS_CREATION} == "true" ]; then
      test "\$abort" == "1" && $WORKSPACE/lcgcmake/cmake/scripts/create_lcg_view.py -l /cvmfs/sft.cern.ch/lcg/releases -p $PLATFORM -r ${LCG_VERSION} -d -B /cvmfs/fcc.cern.ch/sw/views/fccsw/${FCCSW_VERSION}/$PLATFORM
    fi

    if [ "\$?" == "0"  -o ${VIEWS_CREATION} == "false" ]; then
      echo "The creation of the views has worked"
      cd $HOME
      cvmfs_server publish fcc.cern.ch
    else
      echo "The creation of the views has not worked. We exit here"
      cd $HOME
      cvmfs_server abort -f fcc.cern.ch
      exit 1
    fi

elif [[ "${BUILDMODE}" == "limited" ]]; then
    if [[ "${UPDATELINKS}" == "false" ]]; then
        $WORKSPACE/lcgjenkins/lcginstall.py -o -u http://lcgpackages.web.cern.ch/lcgpackages/tarFiles/releases -r ${LCG_VERSION} -d LCG_${LCG_VERSION}_$PLATFORM.txt -p /cvmfs/sft.cern.ch/lcg/releases -e cvmfs
    else
        $WORKSPACE/lcgjenkins/lcginstall.py -o -u http://lcgpackages.web.cern.ch/lcgpackages/tarFiles/releases -r ${LCG_VERSION} -d LCG_${LCG_VERSION}_$PLATFORM.txt --update -p /cvmfs/sft.cern.ch/lcg/releases -e cvmfs
    fi
    $WORKSPACE/lcgcmake/cmake/scripts/create_lcg_view.py -l /cvmfs/sft.cern.ch/lcg/releases/LCG_${LCG_VERSION} -p $PLATFORM -d -B /cvmfs/sft.cern.ch/lcg/views/LCG_${LCG_VERSION}/$PLATFORM
    if [ "\$?" == "0" ]; then
      echo "The creation of the views has worked"
      cd $HOME
      cvmfs_server publish sft.cern.ch
    else
      echo "The creation of the views has not worked. We exit here"
      cd $HOME
      cvmfs_server abort -f sft.cern.ch
      exit 1
    fi
fi
EOF
