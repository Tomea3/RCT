#!/bin/bash
# Enable debug mode to see what's happening in PBS logs
set -x

# Handle arguments
if [ -n "$1" ]; then export SOURCE_DATA=$1; fi
if [ -n "$2" ]; then export DATADIR=$2; fi

# Fallback check
if [ -z "$DATADIR" ]; then
    echo "ERROR: DATADIR is not set. Exiting."
    exit 1
fi

# Define log file
export LOG_FILE="$DATADIR/volume_processing.log"

log_message() {
    local MESSAGE=$1
    # Write to file AND stdout so we see it in PBS logs
    echo "$(date) $MESSAGE" | tee -a "$LOG_FILE"
}

export -f log_message

# Start logging
log_message "$(date) Volume processing job started"
log_message "$PBS_JOBID is running on node `hostname -f`"
test -n "$SCRATCHDIR" && log_message "scratch dir: $SCRATCHDIR"

# Determine script directory (not needed if fetching from git, but kept for reference)
# SCRIPT_DIR=$( dirname "$0" )

# Move into scratch directory
cd $SCRATCHDIR && log_message "move to SCRATCHDIR ok"

# Load git and clone repository
module add git/ && log_message "git loaded" || log_message "git not loaded"
git clone https://github.com/Tomea3/RCT || { echo "Error parsing git clone" >> $LOG_FILE; exit 1; }

# Copy scripts from the Volume_Workflow subdir to scratch root
cp RCT/Volume_Workflow/*.sh . || { echo "Error copying workflow scripts from repo" >> $LOG_FILE; exit 1; }
cp RCT/sys_monitor.sh . 2>/dev/null # Attempt to copy sys_monitor if in root

log_message "Scripts fetched from GitHub"

# Monitor system usage (optional, if sys_monitor exists)
if [ -f "sys_monitor.sh" ]; then
    chmod +x sys_monitor.sh
    ./sys_monitor.sh &
    LSU_PID=$!
fi

# Load singularity
module add singul/ && log_message "singularity loaded"

# Copy data to scratch
source setup_scratch.sh && log_message "setup_scratch ok"

# Process trees (Main Logic)
source process_trees.sh && log_message "process_trees ok"

# Clean up scratch (remove input files to save space if needed, mainly for cleanup)
rm *.laz 2> /dev/null

# Deliver results
source deliver_results.sh && log_message "deliver_results ok"

# Clean scratch directory fully
# clean_scratch # Command not found in some envs
rm -rf "$SCRATCHDIR"/*
exit 0
