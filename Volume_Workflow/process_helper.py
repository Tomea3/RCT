import json
import sys
import math
import os

def generate_ground(filename="ground.txt"):
    # Generate 2x2m grid with 1cm spacing at Z=0
    # Range -1.0 to 1.0 (200 steps each side) implies 2m total width
    # 201 points * 201 points ~ 40k points
    with open(filename, "w") as f:
        f.write("X,Y,Z\n")
        for x in range(-100, 101):
            for y in range(-100, 101):
                f.write(f"{x/100.0},{y/100.0},0.0\n")

def create_pipeline(laz_file, stats_file, output_file, ground_file="ground.txt"):
    try:
        with open(stats_file, "r") as f:
            data = json.load(f)
            
        # Find stats for dimensions X, Y, Z
        stats = data['stats']['statistic']
        
        # Extract bounds
        min_x = next(d['minimum'] for d in stats if d['name'] == 'X')
        max_x = next(d['maximum'] for d in stats if d['name'] == 'X')
        min_y = next(d['minimum'] for d in stats if d['name'] == 'Y')
        max_y = next(d['maximum'] for d in stats if d['name'] == 'Y')
        min_z = next(d['minimum'] for d in stats if d['name'] == 'Z')
        
        # Calculate Translation to (0,0,0)
        # Center in X, Y
        # Bottom at Z=0
        
        center_x = (min_x + max_x) / 2.0
        center_y = (min_y + max_y) / 2.0
        base_z = min_z
        
        offset_x = -center_x
        offset_y = -center_y
        offset_z = -base_z
        
        matrix = f"1 0 0 {offset_x} 0 1 0 {offset_y} 0 0 1 {offset_z} 0 0 0 1"
        
        pipeline = {
            "pipeline": [
                {
                    "type": "readers.text",
                    "filename": ground_file,
                    "header": "X,Y,Z",
                    "spatialreference": "EPSG:32633" # Dummy CRS, maybe not needed or stripped later
                },
                {
                    "type": "readers.las",
                    "filename": laz_file
                },
                {
                    "type": "filters.transformation",
                    "matrix": matrix
                },
                {
                    "type": "filters.merge"
                },
                {
                    "type": "filters.ferry",
                    "dimensions": "X=>GpsTime"
                },
                {
                    "type": "writers.las",
                    "filename": output_file,
                    "minor_version": 2,
                    "dataformat_id": 1
                }
            ]
        }
        
        with open("merge_pipeline.json", "w") as f:
            json.dump(pipeline, f, indent=4)
            
        print(f"Pipeline created. Offset applied: X={offset_x:.2f}, Y={offset_y:.2f}, Z={offset_z:.2f}")
        
    except Exception as e:
        print(f"Error creating pipeline: {e}")
        sys.exit(1)

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "ground":
        generate_ground()
    elif cmd == "pipeline":
        create_pipeline(sys.argv[2], sys.argv[3], sys.argv[4])
