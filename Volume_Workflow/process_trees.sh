#!/bin/bash

# Default Trajectory (dummy) if not provided
# RCT requires GpsTime, so we add it via PDAL.
# We center the tree at 0,0,0 and add a fake ground plane (2x2m).
# Simulated scanner position: 2,2,2.

echo "$(date) Starting tree processing (Fake Ground Workflow)..." >> $LOG_FILE

# Output file for volumes
VOLUME_REPORT="volume_report.csv"
echo "Filename,Volume,SurfaceArea" > $VOLUME_REPORT

# 1. Prepare Ground (once)
# Assuming process_helper.py is in the current directory (copied by master_volume or setup_scratch)
if [ ! -f "process_helper.py" ]; then
    echo "Error: process_helper.py not found!" >> $LOG_FILE
    exit 1
fi

echo "Generating fake ground..." >> $LOG_FILE
python3 process_helper.py ground
if [ ! -f "ground.txt" ]; then
    echo "Error: Failed to generate ground.txt" >> $LOG_FILE
    exit 1
fi

# Iterate over all LAZ files in the directory
for LAZ_FILE in *.laz; do
    [ -e "$LAZ_FILE" ] || continue
    
    # Skip merged files if restart
    if [[ "$LAZ_FILE" == *"_merged.laz"* ]]; then continue; fi
    
    BASENAME=$(basename "$LAZ_FILE" .laz)
    echo "Processing $LAZ_FILE..." >> $LOG_FILE
    
    # 2. PDAL Stats & Center
    # Get stats to calculate offset
    singularity exec -B $SCRATCHDIR/:/data ./pdal.img pdal info --stats "$LAZ_FILE" > stats.json
    
    # create pipeline
    MERGED_LAZ="${BASENAME}_merged.laz"
    python3 process_helper.py pipeline "$LAZ_FILE" stats.json "$MERGED_LAZ"
    
    # Run PDAL pipeline (Merge + Center + Time)
    singularity exec -B $SCRATCHDIR/:/data ./pdal.img pdal pipeline merge_pipeline.json
    
    if [ ! -f "$MERGED_LAZ" ]; then
        echo "Error: Failed to create $MERGED_LAZ" >> $LOG_FILE
        continue
    fi
    
    # 3. RCT Full Pipeline
    
    # A. Import
    # Scanner at 2,2,2
    echo "Importing..." >> $LOG_FILE
    singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayimport "$MERGED_LAZ" ray 2,2,2 --max_intensity 0
    
    IMPORTED_PLY="${MERGED_LAZ%.*}.ply" # rayimport output
    TERRAIN_PLY="${BASENAME}_terrain.ply"
    SEGMENTED_PLY="${BASENAME}_segmented.ply"
    
    # B. Extract Terrain (define ground)
    echo "Extracting terrain..." >> $LOG_FILE
    singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayextract terrain "$IMPORTED_PLY" "$TERRAIN_PLY"
    
    # C. Extract Trees (segmentation)
    # We need dummy files for trunks/forest output, even if we don't use them (check required args)
    # rayextract trees input_cloud input_terrain output_trunks output_forest output_segmented output_trees_txt
    TRUNKS_TXT="${BASENAME}_trunks.txt"
    FOREST_TXT="${BASENAME}_forest.txt"
    TREES_INFO="${BASENAME}_trees.txt"
    
    echo "Extracting trees..." >> $LOG_FILE
    singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayextract trees "$IMPORTED_PLY" "$TERRAIN_PLY" "$TRUNKS_TXT" "$FOREST_TXT" "$SEGMENTED_PLY" "$TREES_INFO"
    
    # D. Segmentation / Export
    # Now we have SEGMENTED_PLY with TreeIDs. We need to split it (export).
    # Create dir for segments
    SEG_DIR="${BASENAME}_segments"
    mkdir -p "$SEG_DIR"
    
    echo "Exporting segments..." >> $LOG_FILE
    singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img rayexport "$SEGMENTED_PLY" "$SEG_DIR/tree"
    
    # E. Process Segments (Wrap & Volume)
    # Loop over exported files
    # shopt -s nullglob
    for SEG_PLY in "$SEG_DIR"/*.ply; do
        SEG_NAME=$(basename "$SEG_PLY" .ply)
        MESH_FILE="${SEG_PLY%.*}_mesh.ply"
        
        echo "Wrapping $SEG_NAME..." >> $LOG_FILE
        # Use alpha 0.2 (robust)
        singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img raywrap "$SEG_PLY" alpha 0.2
        
        # Fallback
        if [ ! -f "$MESH_FILE" ]; then
             singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img raywrap "$SEG_PLY" convexhull
        fi
        
        # TreeInfo / Volume
        if [ -f "$MESH_FILE" ]; then
             echo "Info for $SEG_NAME..." >> $LOG_FILE
             singularity exec -B $SCRATCHDIR/:/data ./raycloudtools.img treeinfo "$MESH_FILE"
             
             # Check output info file
             INFO_TXT="${MESH_FILE%.*}_info.txt"
             if [ -f "$INFO_TXT" ]; then
                 # Append to main log
                 cat "$INFO_TXT" >> $LOG_FILE
                 # Create a copy with nice name in root
                 cp "$INFO_TXT" "${BASENAME}_${SEG_NAME}_info.txt"
             fi
             
             # Also copy mesh to root for delivery
             cp "$MESH_FILE" "${BASENAME}_${SEG_NAME}_mesh.ply"
        fi
    done
    
done

echo "$(date) Processing finished." >> $LOG_FILE

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
    
    # Debug: List files to see what raywrap created
    ls -la >> $LOG_FILE
    
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
