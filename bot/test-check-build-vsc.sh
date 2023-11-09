#!/bin/bash
#
# Script to check the result of building the EESSI software layer.
# Intended use is that it is called by a (batch) job running on a compute
# node.
#
# This script is part of the EESSI software layer, see
# https://github.com/EESSI/software-layer.git
#
# author: Thomas Roeblitz (@trz42)
#
# license: GPLv2
#

# result cases

#  - SUCCESS (all of)
#    - working directory contains slurm-JOBID.out file
#    - working directory contains eessi*tar.gz
#    - no message ERROR
#    - no message FAILED
#    - no message ' required modules missing:'
#    - one or more of 'No missing installations'
#    - module is available on the system
#  - FAILED (one of ... implemented as NOT SUCCESS)
#    - no slurm-JOBID.out file
#    - message with ERROR
#    - message with FAILED
#    - message with ' required modules missing:'
#    - No module was found

# stop as soon as something fails
# set -e

TOPDIR=$(dirname $(realpath $0))

source ${TOPDIR}/../scripts/utils.sh
source ${TOPDIR}/../scripts/cfg_files.sh

# defaults
export JOB_CFG_FILE="${JOB_CFG_FILE_OVERRIDE:=./cfg/job.cfg}"

# check if ${JOB_CFG_FILE} exists
if [[ ! -r "${JOB_CFG_FILE}" ]]; then
    echo_red "job config file (JOB_CFG_FILE=${JOB_CFG_FILE}) does not exist or not readable"
else
    echo "bot/check-build.sh: showing ${JOB_CFG_FILE} from software-layer side"
    cat ${JOB_CFG_FILE}

    echo "bot/check-build.sh: obtaining configuration settings from '${JOB_CFG_FILE}'"
    cfg_load ${JOB_CFG_FILE}
fi

display_help() {
  echo "usage: $0 [OPTIONS]"
  echo " OPTIONS:"
  echo "  -h | --help    - display this usage information [default: false]"
  echo "  -v | --verbose - display more information [default: false]"
}

# set defaults for command line arguments
VERBOSE=0

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      display_help
      exit 0
      ;;
    -v|--verbose)
      VERBOSE=1
      shift 1
      ;;
    --)
      shift
      POSITIONAL_ARGS+=("$@") # save positional args
      break
      ;;
    -*|--*)
      fatal_error "Unknown option: $1" "${CMDLINE_ARG_UNKNOWN_EXITCODE}"
      ;;
    *)  # No more options
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

job_dir=${PWD}

[[ ${VERBOSE} -ne 0 ]] && echo ">> analysing job in directory ${job_dir}"

job_out="slurm-${SLURM_JOB_ID}.out"
[[ ${VERBOSE} -ne 0 ]] && echo ">> searching for job output file(s) matching '"${job_out}"'"
if  [[ -f ${job_out} ]]; then
    SLURM=1
    [[ ${VERBOSE} -ne 0 ]] && echo "   found slurm output file '"${job_out}"'"
else
    SLURM=0
    [[ ${VERBOSE} -ne 0 ]] && echo "   Slurm output file '"${job_out}"' NOT found"
fi

ERROR=-1
if [[ ${SLURM} -eq 1 ]]; then
  GP_error='ERROR: '
  grep_out=$(grep -v "^>> searching for " ${job_dir}/${job_out} | grep "${GP_error}")
  [[ $? -eq 0 ]] && ERROR=1 || ERROR=0
  # have to be careful to not add searched for pattern into slurm out file
  [[ ${VERBOSE} -ne 0 ]] && echo ">> searching for '"${GP_error}"'"
  [[ ${VERBOSE} -ne 0 ]] && echo "${grep_out}"
fi

FAILED=-1
if [[ ${SLURM} -eq 1 ]]; then
  GP_failed='FAILED: '
  grep_out=$(grep -v "^>> searching for " ${job_dir}/${job_out} | grep "${GP_failed}")
  [[ $? -eq 0 ]] && FAILED=1 || FAILED=0
  # have to be careful to not add searched for pattern into slurm out file
  [[ ${VERBOSE} -ne 0 ]] && echo ">> searching for '"${GP_failed}"'"
  [[ ${VERBOSE} -ne 0 ]] && echo "${grep_out}"
fi

MISSING=-1
if [[ ${SLURM} -eq 1 ]]; then
  GP_req_missing=' required modules missing:'
  grep_out=$(grep -v "^>> searching for " ${job_dir}/${job_out} | grep "${GP_req_missing}")
  [[ $? -eq 0 ]] && MISSING=1 || MISSING=0
  # have to be careful to not add searched for pattern into slurm out file
  [[ ${VERBOSE} -ne 0 ]] && echo ">> searching for '"${GP_req_missing}"'"
  [[ ${VERBOSE} -ne 0 ]] && echo "${grep_out}"
fi

NO_MISSING=-1
if [[ ${SLURM} -eq 1 ]]; then
  GP_no_missing='No missing installations'
  grep_out=$(grep -v "^>> searching for " ${job_dir}/${job_out} | grep "${GP_no_missing}")
  [[ $? -eq 0 ]] && NO_MISSING=1 || NO_MISSING=0
  # have to be careful to not add searched for pattern into slurm out file
  [[ ${VERBOSE} -ne 0 ]] && echo ">> searching for '"${GP_no_missing}"'"
  [[ ${VERBOSE} -ne 0 ]] && echo "${grep_out}"
fi

[[ ${VERBOSE} -ne 0 ]] && echo "SUMMARY: ${job_dir}/${job_out}"
[[ ${VERBOSE} -ne 0 ]] && echo "  <test name>: <actual result> (<expected result>)"
[[ ${VERBOSE} -ne 0 ]] && echo "  ERROR......: $([[ $ERROR -eq 1 ]] && echo 'yes' || echo 'no') (no)"
[[ ${VERBOSE} -ne 0 ]] && echo "  FAILED.....: $([[ $FAILED -eq 1 ]] && echo 'yes' || echo 'no') (no)"
[[ ${VERBOSE} -ne 0 ]] && echo "  REQ_MISSING: $([[ $MISSING -eq 1 ]] && echo 'yes' || echo 'no') (no)"
[[ ${VERBOSE} -ne 0 ]] && echo "  NO_MISSING.: $([[ $NO_MISSING -eq 1 ]] && echo 'yes' || echo 'no') (yes)"

job_result_file=_bot_job${SLURM_JOB_ID}.result

if [[ ${SLURM} -eq 1 ]] && \
   [[ ${ERROR} -eq 0 ]] && \
   [[ ${FAILED} -eq 0 ]] && \
   [[ ${MISSING} -eq 0 ]] && \
   [[ ${NO_MISSING} -eq 1 ]]; then
    # SUCCESS
    status="SUCCESS"
    summary=":grin: SUCCESS"
else
    # FAILURE
    status="FAILURE"
    summary=":cry: FAILURE"
fi

### Example details/descriptions
# Note, final string must not contain any line breaks. Below example include
# line breaks for the sake of readability. In case of FAILURE, the structure is
# very similar (incl. information about Artefacts if any was produced), however,
# under Details some lines will be marked with :x:
# <details>
#   <summary>:grin: SUCCESS _(click triangle for details)_</summary>
#   <dl>
#     <dt>_Details_</dt>
#     <dd>
#       :white_check_mark: job output file <code>slurm-4682.out</code><br/>
#       :white_check_mark: no message matching <code>ERROR: </code><br/>
#       :white_check_mark: no message matching <code>FAILED: </code><br/>
#       :white_check_mark: no message matching <code> required modules missing:</code><br/>
#       :white_check_mark: found message(s) matching <code>No missing installations</code><br/>
#       :white_check_mark: found message matching <code>tar.gz created!</code><br/>
#     </dd>
#     <dt>_Artefacts_</dt>
#     <dd>
#       <details>
#         <summary><code>eessi-2023.06-software-linux-x86_64-generic-1682696567.tar.gz</code></summary>
#         size: 234 MiB (245366784 bytes)<br/>
#         entries: 1234<br/>
#         modules under _2023.06/software/linux/x86_64/generic/modules/all/_<br/>
#         <pre>
#           GCC/9.3.0.lua<br/>
#           GCC/10.3.0.lua<br/>
#           OpenSSL/1.1.lua
#         </pre>
#         software under _2023.06/software/linux/x86_64/generic/software/_
#         <pre>
#           GCC/9.3.0/<br/>
#           CMake/3.20.1-GCCcore-10.3.0/<br/>
#           OpenMPI/4.1.1-GCC-10.3.0/
#         </pre>
#         other under _2023.06/software/linux/x86_64/generic/_
#         <pre>
#           .lmod/cache/spiderT.lua<br/>
#           .lmod/cache/spiderT.luac_5.1<br/>
#           .lmod/cache/timestamp
#         </pre>
#       </details>
#     </dd>
#   </dl>
# </details>
#
# <details>
#   <summary>:cry: FAILURE _(click triangle for details)_</summary>
#   <dl>
#     <dt>_Details_</dt>
#     <dd>
#       :white_check_mark: job output file <code>slurm-4682.out</code><br/>
#       :x: no message matching <code>ERROR: </code><br/>
#       :white_check_mark: no message matching <code>FAILED: </code><br/>
#       :x: no message matching <code> required modules missing:</code><br/>
#       :white_check_mark: found message(s) matching <code>No missing installations</code><br/>
#       :white_check_mark: found message matching <code>tar.gz created!</code><br/>
#     </dd>
#     <dt>_module avail check_</dt>
#     <dd>
#       Print the output of module avail name of the installed package.
#     </dd>
#   </dl>
# </details>
###

# construct and write complete PR comment details: implements third alternative
comment_template="<details>__SUMMARY_FMT__<dl>__DETAILS_FMT____ARTEFACTS_FMT__</dl></details>"
comment_summary_fmt="<summary>__SUMMARY__ _(click triangle for details)_</summary>"
comment_details_fmt="<dt>_Details_</dt><dd>__DETAILS_LIST__</dd>"
comment_success_item_fmt=":white_check_mark: __ITEM__"
comment_failure_item_fmt=":x: __ITEM__"
comment_artefacts_fmt="<dt>_Artefacts_</dt><dd>__ARTEFACTS_LIST__</dd>"
comment_artefact_details_fmt="<details>__ARTEFACT_SUMMARY____ARTEFACT_DETAILS__</details>"

function print_br_item() {
    format="${1}"
    item="${2}"
    echo -n "${format//__ITEM__/${item}}<br/>"
}

function print_br_item2() {
    format="${1}"
    item="${2}"
    item2="${3}"
    format1="${format//__ITEM__/${item}}"
    echo -n "${format1//__ITEM2__/${item2}}<br/>"
}

function print_code_item() {
    format="${1}"
    item="${2}"
    echo -n "<code>${format//__ITEM__/${item}}</code>"
}

function print_dd_item() {
    format="${1}"
    item="${2}"
    echo -n "<dd>${format//__ITEM__/${item}}</dd>"
}

function print_list_item() {
    format="${1}"
    item="${2}"
    echo -n "<li>${format//__ITEM__/${item}}</li>"
}

function print_pre_item() {
    format="${1}"
    item="${2}"
    echo -n "<pre>${format//__ITEM__/${item}}</pre>"
}

function success() {
    format="${comment_success_item_fmt}"
    item="$1"
    print_br_item "${format}" "${item}"
}

function failure() {
    format="${comment_failure_item_fmt}"
    item="$1"
    print_br_item "${format}" "${item}"
}

function add_detail() {
    actual=${1}
    expected=${2}
    success_msg="${3}"
    failure_msg="${4}"
    if [[ ${actual} -eq ${expected} ]]; then
        success "${success_msg}"
    else
        failure "${failure_msg}"
    fi
}

echo "[RESULT]" > ${job_result_file}
echo -n "comment_description = " >> ${job_result_file}

# construct values for placeholders in comment_template:
# - __SUMMARY_FMT__ -> variable $comment_summary
# - __DETAILS_FMT__ -> variable $comment_details
# - __ARTEFACTS_FMT__ -> variable $comment_artefacts

comment_summary="${comment_summary_fmt/__SUMMARY__/${summary}}"

# first construct comment_details_list, abbreviated CoDeList
# then use it to set comment_details
CoDeList=""

success_msg="job output file <code>${job_out}</code>"
failure_msg="no job output file <code>${job_out}</code>"
CoDeList=${CoDeList}$(add_detail ${SLURM} 1 "${success_msg}" "${failure_msg}")

success_msg="no message matching <code>${GP_error}</code>"
failure_msg="found message matching <code>${GP_error}</code>"
CoDeList=${CoDeList}$(add_detail ${ERROR} 0 "${success_msg}" "${failure_msg}")

success_msg="no message matching <code>${GP_failed}</code>"
failure_msg="found message matching <code>${GP_failed}</code>"
CoDeList=${CoDeList}$(add_detail ${FAILED} 0 "${success_msg}" "${failure_msg}")

success_msg="no message matching <code>${GP_req_missing}</code>"
failure_msg="found message matching <code>${GP_req_missing}</code>"
CoDeList=${CoDeList}$(add_detail ${MISSING} 0 "${success_msg}" "${failure_msg}")

success_msg="found message(s) matching <code>${GP_no_missing}</code>"
failure_msg="no message matching <code>${GP_no_missing}</code>"
CoDeList=${CoDeList}$(add_detail ${NO_MISSING} 1 "${success_msg}" "${failure_msg}")

comment_details="${comment_details_fmt/__DETAILS_LIST__/${CoDeList}}"

# check for the new software lines added to an easystack
# and than execute a module avail 
IFS=$'\n'
for diff in $(ls *.diff); do
    for ec in $(grep -A20 -e '+++ b/vsc-2022a.yml' ${diff} | tail -n+3); do 
        if [[ ${ec} == +* ]]; then
            if [[ ${ec} == *'.eb' ]]; then 
                name=$(echo ${ec} | cut -d '-' -f 2);
                version=$(echo ${ec} | cut -d '-' -f 3);
                module spider ${name}/${version}
                result=$(module spider ${name}/${version});
            fi;
        fi; 
    done;
done

artefact_summary="<summary>$(print_code_item '__ITEM__' ${name}/${version})</summary>"

CoArList=""
CoArList="${CoArList}$(print_br_item2 ${result})"

comment_artefacts_details="${comment_artefact_details_fmt/__ARTEFACT_SUMMARY__/${artefact_summary}}"
comment_artefacts_details="${comment_artefacts_details/__ARTEFACT_DETAILS__/${CoArList}}"
comment_artefacts="${comment_artefacts_fmt/__ARTEFACTS_LIST__/${comment_artefacts_details}}"

# now put all pieces together creating comment_details from comment_template
comment_description=${comment_template/__SUMMARY_FMT__/${comment_summary}}
comment_description=${comment_description/__DETAILS_FMT__/${comment_details}}
comment_description=${comment_description/__ARTEFACTS_FMT__/${comment_artefacts}}

echo "${comment_description}" >> ${job_result_file}

# add overall result: SUCCESS, FAILURE, UNKNOWN + artefacts
# - this should make use of subsequent steps such as deploying a tarball more
#   efficient
echo "status = ${status}" >> ${job_result_file}

# remove tmpfile
if [[ -f ${tmpfile} ]]; then
    rm ${tmpfile}
fi


# create a module avail command with only the new softwares in the easystack

# exit script with value that reflects overall job result: SUCCESS (0), FAILURE (1)
test "${status}" == "SUCCESS"
exit $?
