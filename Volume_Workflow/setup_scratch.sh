# Copy input data to scratch

# $SOURCE_DATA can be a directory name or a file.
# If it's a directory in $DATADIR, copy its contents.

if [ -d "$DATADIR/$SOURCE_DATA" ]; then
    cp -r "$DATADIR/$SOURCE_DATA"/* $SCRATCHDIR/
    echo "Copied directory contents from $DATADIR/$SOURCE_DATA" >> $LOG_FILE
elif [ -f "$DATADIR/$SOURCE_DATA" ]; then
    cp "$DATADIR/$SOURCE_DATA" $SCRATCHDIR/
    echo "Copied file $DATADIR/$SOURCE_DATA" >> $LOG_FILE
else
    echo "Error: SOURCE_DATA $DATADIR/$SOURCE_DATA not found!" >> $LOG_FILE
    exit 1
fi

# Copy scripts/images if needed (assuming images are in ../../img relative to script, but on cluster paths are absolute)
# We use the paths from original setup_scratch.sh
cp /storage/brno2/home/tomea/RCT/img/raycloudtools.img $SCRATCHDIR || { echo "Error: raycloudtools.img copy failed" >> $LOG_FILE; exit 1; }
cp /storage/brno2/home/tomea/RCT/img/pdal.img $SCRATCHDIR || { echo "Error: pdal.img copy failed" >> $LOG_FILE; exit 1; }

# Copy sys_monitor if it exists in base dir
cp ../sys_monitor.sh $SCRATCHDIR 2>/dev/null
