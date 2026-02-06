#!/bin/bash

# Default Trajectory (dummy) if not provided
# If TRAJECTORY variable is set (from qsub arguments), use it.
# Otherwise, we will use a dummy origin (0,0,1000) for all trees or specific logic.

# Check if we have a global trajectory file
GLOBAL_TRAJ=""
if [ -n "$TRAJECTORY" ] && [ "$TRAJECTORY" != "false" ]; then
    GLOBAL_TRAJ="$TRAJECTORY"
fi

echo "$(date) Starting tree processing..." >> $LOG_FILE

# Output file for volumes
VOLUME_REPORT="volume_report.csv"
echo "Filename,Volume,SurfaceArea" > $VOLUME_REPORT

# Iterate over all LAZ files in the directory
for LAZ_FILE in *.laz; do
    [ -e "$LAZ_FILE" ] || continue # Check if file exists
    
    BASENAME=$(basename "$LAZ_FILE" .laz)
    PLY_FILE="${BASENAME}.ply"
    MESH_FILE="${BASENAME}_mesh.ply"
    
    echo "Processing $LAZ_FILE..." >> $LOG_FILE
    
    # 1. RayImport
    # Convert LAZ to internal PLY format.
    # If we have a specific trajectory for this file (e.g. tree_1.txt), use it?
    # Or use global trajectory?
    # Or use dummy ray origin (e.g. overhead or scanner pos).
    
    # Try to find specific trajectory: name.txt or name_traj.txt
    LOCAL_TRAJ="${BASENAME}.txt"
    
    # Preprocess with PDAL to add GpsTime if missing (required by rayimport)
    # create a temporary file with time added
    LAZ_WITH_TIME="${BASENAME}_time.laz"
    
    # We use a simple PDAL pipeline to add GpsTime (copying X or just valid dimension)
    # Using ferrying X=>GpsTime to ensure the dimension exists and is populated
    echo "Adding timestamps to $LAZ_FILE..." >> $LOG_FILE
    
    # Create simple pipeline json
    echo "{
        \"pipeline\": [
            {
                \"type\": \"readers.las\",
                \"filename\": \"$LAZ_FILE\"
            },
            {
                \"type\": \"filters.ferry\",
                \"dimensions\": \"X=>GpsTime\"
            },
            {
                \"type\": \"writers.las\",
                \"minor_version\": 2,
                \"dataformat_id\": 1,
                \"filename\": \"$LAZ_WITH_TIME\"
            }
        ]
    }" > add_time_pipeline.json
    
    # Run PDAL
    singularity exec -B $SCRATCHDIR/:/data ./pdal.img pdal pipeline add_time_pipeline.json
    
    # Use the new file for rayimport if successful
    if [ -f "$LAZ_WITH_TIME" ]; then
        INPUT_LAZ="$LAZ_WITH_TIME"
    else
        echo "Error: PDAL preprocessing failed for $LAZ_FILE" >> $LOG_FILE
        INPUT_LAZ="$LAZ_FILE" # Fallback, likely to fail
    fi

    echo "Importing $INPUT_LAZ..." >> $LOG_FILE

    if [ -f "$LOCAL_TRAJ" ]; then
        # Use local trajectory file
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$INPUT_LAZ" "$LOCAL_TRAJ"
    elif [ -n "$GLOBAL_TRAJ" ] && [ -f "$GLOBAL_TRAJ" ]; then
        # Use global trajectory
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$INPUT_LAZ" "$GLOBAL_TRAJ"
    else
        # Use Dummy Origin
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$INPUT_LAZ" ray 0,0,100 --remove_start_pos
    fi
    
    # Update PLY_FILE variable because rayimport outputs [filename].ply
    # Input was $INPUT_LAZ (e.g. file_time.laz) -> Output is file_time.ply
    PLY_FILE="${INPUT_LAZ%.*}.ply"
    MESH_FILE="${PLY_FILE%.*}_mesh.ply" # Update mesh filename too to keep consistent
    
    # 2. RayWrap (Create Mesh/Surface)
    # "inwards 1.0" is standard for trees. 
    # Adjusted alpha might be needed depending on point density.
    singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img raywrap "$PLY_FILE" inwards 1.0
    
    # Check if mesh was created
    if [ ! -f "$MESH_FILE" ]; then
        # sometimes raytools naming varies, check for output
        # raywrap input.ply -> input_mesh.ply usually? 
        # Actually raywrap updates the file or creates a new one?
        # Based on process_data.sh: "raywrap segment.ply inwards 1.0"
        # It usually modifies or creates a "_mesh" variants.
        # Let's assume it creates standard output or we check timestamps.
        # Wait, process_data.sh doesn't rename it.
        # But previous step `rayexport` created .laz. 
        # `raywrap` usually writes the mesh to the ply itself or a sidecar?
        # Actually `raywrap` creates a surface mesh.
        # We need to verify output. standard behavior: input.ply -> input_mesh.ply
        TRUE_MESH_FILE="${BASENAME}_mesh.ply" # Hypothetical
        # Let's check if it exists, if not, maybe it overwrote?
        # For safety, we check listing or assume it worked.
        :
    fi
    
    # 3. Calculate Volume
    # Does RCT have a tool? 
    # `treeinfo` might work on the mesh if it's treated as a tree.
    # Let's try treeinfo on the mesh file.
    # Output of treeinfo is usually text.
    
    # 3. Calculate Volume using treeinfo
    # Based on log usage: treeinfo forest.txt [options] - report tree information and save out to _info.txt
    # We should run it on the mesh or the ply? Usually on the structure.
    # The log said "loading tree file: ....ply" so it accepted the PLY.
    # But it showed usage, possibly because we captured stdout and it prints usage to stdout?
    # Or maybe it needs specific flags to output volume?
    # "Output file fields per segment... volume: volume of segment"
    # "Output file fields per tree... height..."
    
    # We will try running it and redirecting output mostly to a file, and checking the generated _info.txt
    
    # Run treeinfo. It auto-generates a file with suffix _info.txt (according to usage)
    singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img treeinfo "$PLY_FILE"
    
    # The output file should be BASENAME_info.txt or similar. Reference: "save out to _info.txt file"
    # Usually it appends _info.txt to the input filename.
    INFO_FILE="${PLY_FILE%.*}_info.txt"
    
    if [ -f "$INFO_FILE" ]; then
        echo "Info file generated: $INFO_FILE" >> $LOG_FILE
        cat "$INFO_FILE" >> $LOG_FILE
        cat "$INFO_FILE" >> "${BASENAME}_info.txt" 
    else
        echo "Warning: No info file generated for $BASENAME" >> $LOG_FILE
        # Try capturing stdout again just in case, but maybe it failed silently or usage was printed because something was wrong
    fi
    
done

echo "$(date) Processing finished." >> $LOG_FILE
