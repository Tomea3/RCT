#!/bin/bash

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
