#!/bin/bash
#
# This script creates a ReFrame config file from a template, in which CPU properties get replaced
# based on where this script is run (typically: a build node). Then, it runs the EESSI test suite.
#
# This script is part of the EESSI software layer, see
# https://github.com/EESSI/software-layer.git
#
# author: Caspar van Leeuwen (@casparvl)
#
# license: GPLv2

display_help() {
  echo "usage: $0 [OPTIONS]"
  echo "  -g | --generic         -  instructs script to test for generic architecture target"
  echo "  -h | --help            -  display this usage information"
  echo "  -x | --http-proxy URL  -  provides URL for the environment variable http_proxy"
  echo "  -y | --https-proxy URL -  provides URL for the environment variable https_proxy"
}

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -g|--generic)
      DETECTION_PARAMETERS="--generic"
      shift
      ;;
    -h|--help)
      display_help  # Call your function
      # no shifting needed here, we're done.
      exit 0
      ;;
    -x|--http-proxy)
      export http_proxy="$2"
      shift 2
      ;;
    -y|--https-proxy)
      export https_proxy="$2"
      shift 2
      ;;
    --build-logs-dir)
      export build_logs_dir="${2}"
      shift 2
      ;;
    --shared-fs-path)
      export shared_fs_path="${2}"
      shift 2
      ;;
    -*|--*)
      echo "Error: Unknown option: $1" >&2
      exit 1
      ;;
    *)  # No more options
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

TOPDIR=$(dirname $(realpath $0))

source $TOPDIR/scripts/utils.sh

# honor $TMPDIR if it is already defined, use /tmp otherwise
if [ -z $TMPDIR ]; then
    export WORKDIR=/tmp/$USER
else
    export WORKDIR=$TMPDIR/$USER
fi

TMPDIR=$(mktemp -d)

echo ">> Setting up environment..."
# For this call to be succesful, it needs to be able to import archspec (which is part of EESSI)
# Thus, we execute it in a subshell where EESSI is already initialized (a bit like a bootstrap)
export EESSI_SOFTWARE_SUBDIR_OVERRIDE=$(source $TOPDIR/init/bash > /dev/null 2>&1; python3 $TOPDIR/eessi_software_subdir.py $DETECTION_PARAMETERS)
echo "EESSI_SOFTWARE_SUBDIR_OVERRIDE: $EESSI_SOFTWARE_SUBDIR_OVERRIDE"

source $TOPDIR/init/bash

# We have to ignore the LMOD cache, otherwise the software that is built in the build step cannot be found/loaded
# Reason is that the LMOD cache is normally only updated on the Stratum 0, once everything is ingested
export LMOD_IGNORE_CACHE=1

software_layer_dir=$(dirname $(realpath $0))
source $software_layer_dir/scripts/cfg_files.sh

# defaults
export JOB_CFG_FILE="${JOB_CFG_FILE_OVERRIDE:=cfg/job.cfg}"
HOST_ARCH=$(uname -m)

# check if ${JOB_CFG_FILE} exists
if [[ ! -r "${JOB_CFG_FILE}" ]]; then
    fatal_error "job config file (JOB_CFG_FILE=${JOB_CFG_FILE}) does not exist or not readable"
fi
echo "test_suite.sh: showing ${JOB_CFG_FILE} from software-layer side"
cat ${JOB_CFG_FILE}

echo "test_suite.sh: obtaining configuration settings from '${JOB_CFG_FILE}'"
cfg_load ${JOB_CFG_FILE}

echo "test_suite.sh: MODULEPATH='${MODULEPATH}'"
export EESSI_ACCELERATOR_TARGET=$(cfg_get_value "architecture" "accelerator")
echo "test_suite.sh: EESSI_ACCELERATOR_TARGET='${EESSI_ACCELERATOR_TARGET}'"
# Load the ReFrame module
# Currently, we load the default version. Maybe we should somehow make this configurable in the future?
module load ReFrame
if [[ $? -eq 0 ]]; then
    echo_green ">> Loaded ReFrame module"
else
    fatal_error "Failed to load the ReFrame module"
fi

# Check that a system python3 is available
python3_found=$(command -v python3)
if [ -z ${python3_found} ]; then
    fatal_error "No system python3 found"
else
    echo_green "System python3 found:"
    python3 -V
fi

# Check ReFrame came with the hpctestlib and we can import it
reframe_import="hpctestlib.sciapps.gromacs"
python3 -c "import ${reframe_import}"
if [[ $? -eq 0 ]]; then
    echo_green "Succesfully found and imported ${reframe_import}"
else
    fatal_error "Failed to import ${reframe_import}"
fi

# Cloning should already be done in run_tests.sh before test_suite.sh is invoked
# Check if that succeeded
export TESTSUITEPREFIX=$PWD/EESSI-test-suite
if [ -d $TESTSUITEPREFIX ]; then
    echo_green "Clone of the test suite $TESTSUITEPREFIX available, OK!"
else
    fatal_error "Clone of the test suite $TESTSUITEPREFIX is not available!"
fi
export PYTHONPATH=$TESTSUITEPREFIX:$PYTHONPATH

# Check that we can import from the testsuite
testsuite_import="eessi.testsuite"
python3 -c "import ${testsuite_import}"
if [[ $? -eq 0 ]]; then
    echo_green "Succesfully found and imported ${testsuite_import}"
else
    fatal_error "Failed to import ${testsuite_import}"
fi

# Configure ReFrame, see https://www.eessi.io/docs/test-suite/installation-configuration
# RFM_CONFIG_FILES _has_ to be set by the site hosting the bot, so that it knows where to find the ReFrame
# config file that matches the bot config. See https://gitlab.com/eessi/support/-/issues/114#note_2293660921
if [ -z "$RFM_CONFIG_FILES" ]; then
    err_msg="Please set RFM_CONFIG_FILES in the environment of this bot instance to point to a valid"
    err_msg="${err_msg} ReFrame configuration file that matches the bot config."
    err_msg="${err_msg} For more information, see https://gitlab.com/eessi/support/-/issues/114#note_2293660921"
    fatal_error "${err_msg}"
fi
export RFM_CHECK_SEARCH_PATH=$TESTSUITEPREFIX/eessi/testsuite/tests
export RFM_CHECK_SEARCH_RECURSIVE=1
export RFM_PREFIX=$PWD/reframe_runs

# Get the correct partition name
REFRAME_PARTITION_NAME=${EESSI_SOFTWARE_SUBDIR//\//_}
if [ ! -z "$EESSI_ACCELERATOR_TARGET" ]; then
    REFRAME_PARTITION_NAME=${REFRAME_PARTITION_NAME}_${EESSI_ACCELERATOR_TARGET//\//_}
fi
echo "Constructed partition name based on EESSI_SOFTWARE_SUBDIR and EESSI_ACCELERATOR_TARGET: ${REFRAME_PARTITION_NAME}"

# Set the reframe system name, including partition
export RFM_SYSTEM="BotBuildTests:${REFRAME_PARTITION_NAME}"

echo "Configured reframe with the following environment variables:"
env | grep "RFM_"

# THIS WHOLE BLOCK SHOULD NO LONGER BE NEEDED IF WE HAVE SITE-SPECIFIC CONFIG FILES
# # The /sys inside the container is not the same as the /sys of the host
# # We want to extract the memory limit from the cgroup on the host (which is typically set by SLURM).
# # Thus, bot/test.sh bind-mounts the host's /sys/fs/cgroup into /hostsys/fs/cgroup
# # and that's the prefix we use to extract the memory limit from
# cgroup_v1_mem_limit="/hostsys/fs/cgroup/memory/$(</proc/self/cpuset)/memory.limit_in_bytes"
# cgroup_v2_mem_limit="/hostsys/fs/cgroup/$(</proc/self/cpuset)/memory.max"
# if [ -f "$cgroup_v1_mem_limit" ]; then
#     echo "Getting memory limit from file $cgroup_v1_mem_limit"
#     cgroup_mem_bytes=$(cat "$cgroup_v1_mem_limit")
# elif [ -f "$cgroup_v2_mem_limit" ]; then
#     echo "Getting memory limit from file $cgroup_v2_mem_limit"
#     cgroup_mem_bytes=$(cat "$cgroup_v2_mem_limit")
#     if [ "$cgroup_mem_bytes" = 'max' ]; then
#         # In cgroupsv2, the memory.max file may contain 'max', meaning the group can use the full system memory
#         # Here, we get the system memory from /proc/meminfo. Units are supposedly always in kb, but lets match them too
#         cgroup_mem_kilobytes=$(grep -oP 'MemTotal:\s+\K\d+(?=\s+kB)' /proc/meminfo)
#         if [[ $? -ne 0 ]] || [[ -z "$cgroup_mem_kilobytes" ]]; then
#             fatal_error "Failed to get memory limit from /proc/meminfo"
#         fi
#         cgroup_mem_bytes=$(("$cgroup_mem_kilobytes"*1024))
#     fi
# else
#     fatal_error "Both files ${cgroup_v1_mem_limit} and ${cgroup_v2_mem_limit} couldn't be found. Failed to get the memory limit from the current cgroup"
# fi
# if [[ $? -eq 0 ]]; then
#     # Convert to MiB
#     cgroup_mem_mib=$(("$cgroup_mem_bytes"/(1024*1024)))
# else
#     fatal_error "Failed to get the memory limit in bytes from the current cgroup"
# fi
# echo "Detected available memory: ${cgroup_mem_mib} MiB"
# 
# cp ${RFM_CONFIG_FILE_TEMPLATE} ${RFM_CONFIG_FILES}
# echo "Replacing memory limit in the ReFrame config file with the detected CGROUP memory limit: ${cgroup_mem_mib} MiB"
# sed -i "s/__MEM_PER_NODE__/${cgroup_mem_mib}/g" $RFM_CONFIG_FILES
# RFM_PARTITION="${SLURM_JOB_PARTITION}"
# echo "Replacing partition name in the template ReFrame config file: ${RFM_PARTITION}"
# sed -i "s/__RFM_PARTITION__/${RFM_PARTITION}/g" $RFM_CONFIG_FILES

# Make debugging easier by printing the final config file:
echo "ReFrame config file used:"
cat "${RFM_CONFIG_FILES}"

# Workaround for https://github.com/EESSI/software-layer/pull/467#issuecomment-1973341966
export PSM3_DEVICES='self,shm'  # this is enough, since we only run single node for now

# Check we can run reframe
reframe --version
if [[ $? -eq 0 ]]; then
    echo_green "Succesfully ran 'reframe --version'"
else
    fatal_error "Failed to run 'reframe --version'"
fi

# Get the subset of test names based on the test mapping and tags (e.g. CI, 1_node)
module_list="module_files.list.txt"
mapping_config="tests/eessi_test_mapping/software_to_tests.yml"
if [[ ! -f "$module_list" ]]; then
    echo_green "File ${module_list} not found, so only running the default set of tests from ${mapping_config}"
    # Run with --debug for easier debugging in case there are issues:
    python3 tests/eessi_test_mapping/map_software_to_test.py --mapping-file "${mapping_config}" --debug --defaults-only
    REFRAME_NAME_ARGS=$(python3 tests/eessi_test_mapping/map_software_to_test.py --mapping-file "${mapping_config}" --defaults-only)
    test_selection_exit_code=$?
else
    # Run with --debug for easier debugging in case there are issues:
    python3 tests/eessi_test_mapping/map_software_to_test.py --module-list "${module_list}" --mapping-file "${mapping_config}" --debug
    REFRAME_NAME_ARGS=$(python3 tests/eessi_test_mapping/map_software_to_test.py --module-list "${module_list}" --mapping-file "${mapping_config}")
    test_selection_exit_code=$?
fi
# Check exit status
if [[ ${test_selection_exit_code} -eq 0 ]]; then
    echo_green "Succesfully extracted names of tests to run: ${REFRAME_NAME_ARGS}"
else
    fatal_error "Failed to extract names of tests to run: ${REFRAME_NAME_ARGS}"
    exit ${test_selection_exit_code}
fi
# Allow people deploying the bot to overrwide this
if [ -z "$REFRAME_SCALE_TAG" ]; then
    REFRAME_SCALE_TAG=--tag=1_4_node
fi
if [ -z "$REFRAME_CI_TAG" ]; then
    REFRAME_CI_TAG=--tag=CI
fi
# Allow bot-deployers to add additional args through the environment
if [ -z "$REFRAME_ADDITIONAL_ARGS" ]; then
    REFRAME_ADDITIONAL_ARGS=""
fi
export REFRAME_ARGS="${REFRAME_NAME_ARGS}"

# List the tests we want to run
echo "Listing tests: reframe ${REFRAME_ARGS} --list"
reframe ${REFRAME_CI_TAG} ${REFRAME_SCALE_TAG} ${REFRAME_ADDITIONAL_ARGS} --nocolor ${REFRAME_ARGS} --list -v
if [[ $? -eq 0 ]]; then
    echo_green "Succesfully listed ReFrame tests with command: reframe ${REFRAME_ARGS} --list"
else
    fatal_error "Failed to list ReFrame tests with command: reframe ${REFRAME_ARGS} --list"
fi

# Run all tests
echo "Running tests: reframe ${REFRAME_ARGS} --run"
reframe ${REFRAME_CI_TAG} ${REFRAME_SCALE_TAG} ${REFRAME_ADDITIONAL_ARGS} --nocolor ${REFRAME_ARGS} --run
reframe_exit_code=$?
if [[ ${reframe_exit_code} -eq 0 ]]; then
    echo_green "ReFrame runtime ran succesfully with command: reframe ${REFRAME_ARGS} --run."
else
    fatal_error "ReFrame runtime failed to run with command: reframe ${REFRAME_ARGS} --run."
fi

echo ">> Cleaning up ${TMPDIR}..."
rm -r ${TMPDIR}

exit ${reframe_exit_code}
