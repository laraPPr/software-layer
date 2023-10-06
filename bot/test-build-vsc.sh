#!/usr/bin/env bash
#
# script to build the software for VSC. Intended use is that it is called
# by a (batch) job running on a compute node.
#
# This script is based on a script that is part of the EESSI software layer, 
# written by Thomas Roeblitz (@trz42), 
# see https://github.com/EESSI/software-layer.git
#
# license: GPLv2
#
# author: Lara Peeters (laraPPr)

# ASSUMPTIONs:
#  - working directory has been prepared by the bot with a checkout of a
#    pull request (OR by some other means)
#  - the working directory contains a directory 'cfg' where the main config
#    file 'job.cfg' has been deposited
#  - the directory may contain any additional files referenced in job.cfg

# stop as soon as something fails
set -e

# source utils.sh
source scripts/utils.sh

echo_green "All set, let's start installing some software with EasyBuild Dev in ${EASYBUILD_INSTALLPATH}..."

for es in $(ls vsc-*.yml); do
    if [ -f ${es} ]; then
        echo_green "Feeding easystack file ${es} to EasyBuild..."
        echo ${EB} --easystack ${es} --robot
        #ec=$?

    else
        fatal_error "Easystack file ${es} not found!"
    fi
done

echo ">> Cleaning up ${TMPDIR}..."
rm -r ${TMPDIR}
