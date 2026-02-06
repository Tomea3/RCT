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
    echo "Adding timestamps to $LAZ_FILE..." >> $LOG_FILE
    
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
    
    singularity exec -B $SCRATCHDIR/:/data ./pdal.img pdal pipeline add_time_pipeline.json
    
    if [ -f "$LAZ_WITH_TIME" ]; then
        INPUT_LAZ="$LAZ_WITH_TIME"
    else
        echo "Error: PDAL preprocessing failed for $LAZ_FILE" >> $LOG_FILE
        INPUT_LAZ="$LAZ_FILE"
    fi

    echo "Importing $INPUT_LAZ..." >> $LOG_FILE

    # RayImport with --max_intensity 0 to suppress warnings about missing intensity
    if [ -f "$LOCAL_TRAJ" ]; then
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$INPUT_LAZ" "$LOCAL_TRAJ" --max_intensity 0
    elif [ -n "$GLOBAL_TRAJ" ] && [ -f "$GLOBAL_TRAJ" ]; then
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$INPUT_LAZ" "$GLOBAL_TRAJ" --max_intensity 0
    else
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$INPUT_LAZ" ray 0,0,100 --remove_start_pos --max_intensity 0
    fi
    
    # Update filenames logic
    PLY_FILE="${INPUT_LAZ%.*}.ply"
    MESH_FILE="${PLY_FILE%.*}_mesh.ply"
    
    # RayWrap: Try alpha 0.2 first (stable for most trees)
    echo "Running raywrap alpha 0.2..." >> $LOG_FILE
    singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img raywrap "$PLY_FILE" alpha 0.2
    
    # Fallback to convexhull if alpha failed
    if [ ! -f "$MESH_FILE" ]; then
        echo "Raywrap alpha failed. Trying convexhull..." >> $LOG_FILE
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img raywrap "$PLY_FILE" convexhull
    fi
    
    # TreeInfo (Volume Calculation) on Mesh
    if [ -f "$MESH_FILE" ]; then
         echo "Running treeinfo on mesh: $MESH_FILE" >> $LOG_FILE
         singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img treeinfo "$MESH_FILE"
         
         # Capture output (auto-generated _info.txt)
         INFO_FILE="${MESH_FILE%.*}_info.txt"
         if [ -f "$INFO_FILE" ]; then
             echo "Info file generated: $INFO_FILE" >> $LOG_FILE
             cat "$INFO_FILE" >> $LOG_FILE
             cat "$INFO_FILE" >> "${BASENAME}_info.txt" 
         else
             echo "Warning: No info file generated from $MESH_FILE" >> $LOG_FILE
         fi
    else
         echo "Error: Mesh file $MESH_FILE not found (raywrap failed?)" >> $LOG_FILE
    fi
    
done

echo "$(date) Processing finished." >> $LOG_FILE
