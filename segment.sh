#!/bin/bash
source /etc/profile.d/modules.sh

# move to scratch
cd $SCRATCHDIR
# get source code
module add git/ && echo "git loaded" >> $LOG_FILE || echo "git not loaded" >> $LOG_FILE
git clone https://github.com/Tomea3/RCT
cp RCT/*.sh $SCRATCHDIR

# set variables
export SOURCE_DATA=$1 # First argument is the input file (e.g., cloud_name) without extension
export DATADIR=$2 # Second argument is the dir path (e.g., /storage/plzen1/home/krucek/gs-lcr/001)

export VOXELIZE=${3:-true}
export VOXEL_RES=${4:-0.02}
export ADD_TIME=${5:-true}
export TRAJECTORY=${6:-false}



# process
source $SCRATCHDIR/master_processor.sh 


