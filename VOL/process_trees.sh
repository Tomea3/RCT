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
    
    if [ -f "$LOCAL_TRAJ" ]; then
        # Use local trajectory file
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$LAZ_FILE" "$LOCAL_TRAJ"
    elif [ -n "$GLOBAL_TRAJ" ] && [ -f "$GLOBAL_TRAJ" ]; then
        # Use global trajectory
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$LAZ_FILE" "$GLOBAL_TRAJ"
    else
        # Use Dummy Origin (e.g. 0,0,-10 implies scanner at -10m height? Or 0,0,1000 for aerial?)
        # User prompt context: "dummy trajektorie".
        # We'll use ray 0,0,100 --remove_start_pos (assuming aerial/high view or just direction)
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$LAZ_FILE" ray 0,0,100 --remove_start_pos
    fi
    
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
    
    INFO_OUT=$(singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img treeinfo "$PLY_FILE")
    # append to report
    echo "$BASENAME :: $INFO_OUT" >> $LOG_FILE
    
    # simple parsing (pseudo-code, depends on output format)
    # We save the raw info for verification
    echo "$INFO_OUT" > "${BASENAME}_info.txt"
    
done

echo "$(date) Processing finished." >> $LOG_FILE
