
log_message "deliver results start"

# Create a simplified ZIP with just the reports and meshes (optional)
# Or zip everything including logs.

ZIP_NAME="Volume_Results_${PBS_JOBID}.zip"

# Zip all .csv reports, .txt info, and _mesh.ply files
zip -r "$ZIP_NAME" *.csv *.txt *_mesh.ply volume_processing.log

echo "$(date) compressed" >> $LOG_FILE

# Copy back
cp "$ZIP_NAME" $DATADIR/
echo "$(date) Copied $ZIP_NAME to $DATADIR" >> $LOG_FILE
