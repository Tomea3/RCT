#!/usr/bin/env python3
"""
Windows: Příprava LAZ stromů pro RayExtract
============================================
1. Načte LAZ soubory stromů
2. Přidá umělou zem (plane.laz nebo vygeneruje)
3. Spočítá normály směrem ke skeneru
4. Uloží jako binární PLY

Požadavky:
    pip install laspy numpy open3d

Použití:
    python prepare_trees.py input_folder output_folder [--plane plane.laz]
"""

import os
import sys
import argparse
import numpy as np

try:
    import laspy
except ImportError:
    print("ERROR: Install laspy: pip install laspy")
    sys.exit(1)

try:
    import open3d as o3d
except ImportError:
    print("ERROR: Install open3d: pip install open3d")
    sys.exit(1)


def create_ground_plane(center_x, center_y, size=20.0, z=0.0, density=0.1):
    """Vytvoří umělou zem jako grid bodů."""
    n_points = int(size / density)
    x = np.linspace(center_x - size/2, center_x + size/2, n_points)
    y = np.linspace(center_y - size/2, center_y + size/2, n_points)
    xx, yy = np.meshgrid(x, y)
    zz = np.full_like(xx, z)
    
    points = np.column_stack([xx.ravel(), yy.ravel(), zz.ravel()])
    return points


def process_laz_file(laz_path, output_path, plane_path=None, scanner_pos=(5, 5, 2)):
    """Zpracuje jeden LAZ soubor stromu."""
    print(f"  Processing: {os.path.basename(laz_path)}")
    
    # Načíst LAZ
    las = laspy.read(laz_path)
    tree_points = np.column_stack([las.x, las.y, las.z])
    
    # Statistiky stromu
    min_xyz = tree_points.min(axis=0)
    max_xyz = tree_points.max(axis=0)
    center_x = (min_xyz[0] + max_xyz[0]) / 2
    center_y = (min_xyz[1] + max_xyz[1]) / 2
    base_z = min_xyz[2]
    height = max_xyz[2] - min_xyz[2]
    
    print(f"    Bounds: X=[{min_xyz[0]:.2f}, {max_xyz[0]:.2f}], "
          f"Y=[{min_xyz[1]:.2f}, {max_xyz[1]:.2f}], "
          f"Z=[{min_xyz[2]:.2f}, {max_xyz[2]:.2f}]")
    print(f"    Height: {height:.2f}m, Base Z: {base_z:.2f}m")
    
    # Načíst nebo vytvořit zem
    if plane_path and os.path.exists(plane_path):
        print(f"    Loading ground plane: {plane_path}")
        plane_las = laspy.read(plane_path)
        ground_points = np.column_stack([plane_las.x, plane_las.y, plane_las.z])
    else:
        print(f"    Generating ground plane at Z={base_z:.2f}")
        size = max(max_xyz[0] - min_xyz[0], max_xyz[1] - min_xyz[1]) + 10
        ground_points = create_ground_plane(center_x, center_y, size=size, z=base_z, density=0.2)
    
    # Sloučit body
    all_points = np.vstack([tree_points, ground_points])
    print(f"    Total points: {len(all_points)} (tree: {len(tree_points)}, ground: {len(ground_points)})")
    
    # Vytvořit Open3D point cloud
    pcd = o3d.geometry.PointCloud()
    pcd.points = o3d.utility.Vector3dVector(all_points)
    
    # Spočítat normály
    print(f"    Computing normals (sensor at {scanner_pos})...")
    pcd.estimate_normals(search_param=o3d.geometry.KDTreeSearchParamHybrid(radius=0.5, max_nn=30))
    
    # Orientovat normály ke skeneru
    # Pozice skeneru relativně k centru stromu
    sensor_absolute = np.array([center_x + scanner_pos[0], 
                                center_y + scanner_pos[1], 
                                base_z + scanner_pos[2]])
    pcd.orient_normals_towards_camera_location(sensor_absolute)
    
    # Uložit jako binární PLY
    o3d.io.write_point_cloud(output_path, pcd, write_ascii=False)
    
    file_size = os.path.getsize(output_path) / 1024
    print(f"    Saved: {output_path} ({file_size:.1f} KB)")
    
    return {
        "input": laz_path,
        "output": output_path,
        "points": len(all_points),
        "height": height
    }


def main():
    parser = argparse.ArgumentParser(description="Prepare LAZ trees for RayExtract")
    parser.add_argument("input_folder", help="Folder with LAZ tree files")
    parser.add_argument("output_folder", help="Output folder for PLY files")
    parser.add_argument("--plane", help="Optional: ground plane LAZ file", default=None)
    parser.add_argument("--scanner", help="Scanner position offset (x,y,z)", default="5,5,2")
    args = parser.parse_args()
    
    # Parse scanner position
    scanner_pos = tuple(float(x) for x in args.scanner.split(","))
    
    # Vytvořit output folder
    os.makedirs(args.output_folder, exist_ok=True)
    
    # Najít LAZ soubory
    laz_files = [f for f in os.listdir(args.input_folder) if f.lower().endswith(".laz")]
    
    if not laz_files:
        print(f"No LAZ files found in {args.input_folder}")
        return
    
    print(f"Found {len(laz_files)} LAZ files")
    print(f"Scanner position offset: {scanner_pos}")
    print("="*60)
    
    results = []
    for laz_file in laz_files:
        laz_path = os.path.join(args.input_folder, laz_file)
        output_path = os.path.join(args.output_folder, laz_file.replace(".laz", ".ply").replace(".LAZ", ".ply"))
        
        try:
            result = process_laz_file(laz_path, output_path, args.plane, scanner_pos)
            results.append(result)
        except Exception as e:
            print(f"  ERROR: {e}")
    
    print("="*60)
    print(f"Processed {len(results)}/{len(laz_files)} files")
    print(f"Output folder: {args.output_folder}")


if __name__ == "__main__":
    main()