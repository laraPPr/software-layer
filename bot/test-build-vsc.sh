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

EB='eb --detect-loaded-modules=purge --experimental'

echo_green "All set, let's start installing some software with EasyBuild Dev in ${EASYBUILD_INSTALLPATH}..."

for es in $(ls vsc-*.yml); do
    if [ -f ${es} ]; then
        echo_green "checking easybuild version"
        export PATH=$HOME/.local/bin:$PATH
        export PYTHONPATH=$HOME/.local/lib/python3.8/site-packages/:$PYTHONPATH
        echo "using local pip install of easybuild with python3.8"
        ${EB} --version

        echo_green "Feeding easystack file ${es} to EasyBuild..."
        ${EB} --easystack ${es} --robot
        ec=$?

    else
        fatal_error "Easystack file ${es} not found!"
    fi
    ./check_missing_installations.sh ${es}
done

echo ">> Cleaning up ${TMPDIR}..."
rm -r ${TMPDIR}
