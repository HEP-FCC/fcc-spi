#---Utility Macros----------------------------------------------------------
include(${CTEST_SCRIPT_DIRECTORY}/macros.cmake)

#---General Configuration---------------------------------------------------
GET_HOST(host)
GET_NCPUS(ncpu)
GET_CONFIGURATION_TAG(tag)
GET_CTEST_BUILD_NAME(CTEST_BUILD_NAME)

#--Package configuration----------------------------------------------------
SET(PKG_NAME fccsw)

#--Required variables-------------------------------------------------------
set(CTEST_CMAKE_GENERATOR "Unix Makefiles")
set(CTEST_SITE "${host}")

#---CDash slot name---------------------------------------------------------
# Nightly, Experimental, PullRequests...

if(NOT "$ENV{ghprbPullId}" STREQUAL "")
  set(CTEST_BUILD_NAME "PR-$ENV{ghprbPullId}-${CTEST_BUILD_NAME}")
  set(dashboard_model PullRequests)
elseif("$ENV{CDASH_LABEL}" STREQUAL "Nightly")
  set(dashboard_model Nightly)
  set(CTEST_BUILD_NAME "$ENV{sha1}-${CTEST_BUILD_NAME}")
else()
  set(dashboard_model Experimental)
  set(CTEST_BUILD_NAME "$ENV{sha1}-${CTEST_BUILD_NAME}")
endif()
message("Running a ${dashboard_model} build: ${CTEST_BUILD_NAME}")


#---Build and configure type------------------------------------------------
if(NOT "$ENV{BUILDTYPE}" STREQUAL "")
  set(CTEST_BUILD_CONFIGURATION $ENV{BUILDTYPE})
  set(CTEST_CONFIGURATION_TYPE ${CTEST_BUILD_CONFIGURATION})
endif()

#---Set the source and build directory--------------------------------------
set(CTEST_BUILD_PREFIX "$ENV{WORKSPACE}")
set(CTEST_SOURCE_DIRECTORY "${CTEST_BUILD_PREFIX}/${PKG_NAME}")
set(CTEST_BINARY_DIRECTORY "${CTEST_BUILD_PREFIX}/${PKG_NAME}/build.$ENV{BINARY_TAG}")

#---Create build directory--------------------------------------------------
if(NOT "${CTEST_BINARY_DIRECTORY}")
  message("Creating build directory...")
  file(MAKE_DIRECTORY "${CTEST_BINARY_DIRECTORY}")
endif()

#---Custom build command----------------------------------------------------
# Run build step in parallel using the maximum number of jobs
set(CTEST_BUILD_COMMAND "make -j${ncpu}")


# not a ctest variable, but used in custom cmake macro
set(CTEST_TEST_PARALLEL_LEVEL 1)

set(CTEST_TEST_LOAD ${ncpu})



#---CDash settings----------------------------------------------------------
set(CTEST_PROJECT_NAME "FCC")
set(CTEST_NIGHTLY_START_TIME "01:00:00 UTC")
set(CTEST_DROP_METHOD "http")
set(CTEST_DROP_SITE "cdash.cern.ch")
set(CTEST_DROP_LOCATION "/submit.php?project=FCC")
set(CTEST_DROP_SITE_CDASH TRUE)

#---Custom CTest settings---------------------------------------------------
set(CTEST_CUSTOM_MAXIMUM_FAILED_TEST_OUTPUT_SIZE "1000000")
set(CTEST_CUSTOM_MAXIMUM_PASSED_TEST_OUTPUT_SIZE "100000")
set(CTEST_CUSTOM_MAXIMUM_NUMBER_OF_ERRORS "256")
set(CTEST_TEST_TIMEOUT 1500)


#--Common options-----------------------------------------------------------
include(${CTEST_SCRIPT_DIRECTORY}/cmake_common.cmake)
