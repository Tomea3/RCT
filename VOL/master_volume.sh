#!/bin/bash

# Handle arguments if provided (alternative to environment variables)
# Usage: ./master_volume.sh [SOURCE_DATA] [DATADIR]
if [ -n "$1" ]; then export SOURCE_DATA=$1; fi
if [ -n "$2" ]; then export DATADIR=$2; fi

# Define log file
export LOG_FILE="$DATADIR/volume_processing.log"

log_message() {
    local MESSAGE=$1
    echo "$(date) $MESSAGE" >> $LOG_FILE
}

export -f log_message

# Start logging
log_message "$(date) Volume processing job started"
log_message "$PBS_JOBID is running on node `hostname -f`"
test -n "$SCRATCHDIR" && log_message "scratch dir: $SCRATCHDIR"

# Determine script directory to find dependency scripts
SCRIPT_DIR=$( dirname "$0" )

# Copy dependency scripts to SCRATCHDIR before moving there
cp "$SCRIPT_DIR/setup_scratch.sh" "$SCRATCHDIR/" || { echo "Error copying setup_scratch.sh" >> $LOG_FILE; exit 1; }
cp "$SCRIPT_DIR/process_trees.sh" "$SCRATCHDIR/" || { echo "Error copying process_trees.sh" >> $LOG_FILE; exit 1; }
cp "$SCRIPT_DIR/deliver_results.sh" "$SCRATCHDIR/" || { echo "Error copying deliver_results.sh" >> $LOG_FILE; exit 1; }

# Try to copy sys_monitor if it exists (check parent dir too)
cp "$SCRIPT_DIR/sys_monitor.sh" "$SCRATCHDIR/" 2>/dev/null || cp "$SCRIPT_DIR/../sys_monitor.sh" "$SCRATCHDIR/" 2>/dev/null

# Move into scratch directory
cd $SCRATCHDIR && log_message "move to SCRATCHDIR ok"

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
clean_scratch
exit 0
