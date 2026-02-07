#!/usr/bin/env python3
"""
Metacentrum: Batch RayExtract Volume Calculation
=================================================
Zpracuje všechny PLY soubory a spočítá objem stromů.

Použití:
    python process_volumes.py input_folder output_folder

Požadavky:
    - Singularity image: raycloudtools.img
    - PLY soubory připravené pomocí prepare_trees.py (s normálami)
"""

import os
import sys
import json
import struct
import subprocess
import argparse
from pathlib import Path


# Konfigurace
SINGULARITY_IMAGE = "raycloudtools.img"
SCANNER_POS = "5,5,2"  # Pozice skeneru


def run_singularity(image, cmd, workdir=None, bind_paths=None):
    """Spustí příkaz v Singularity kontejneru."""
    if workdir is None:
        workdir = os.getcwd()
    
    # Konvertovat na absolutní cestu
    workdir = os.path.abspath(workdir)
    
    # Bind paths - vždy absolutní
    binds = [workdir]
    if bind_paths:
        for p in bind_paths:
            abs_p = os.path.abspath(p)
            if abs_p not in binds:
                binds.append(abs_p)
    
    # Sestavit bind string - Singularity format: path1:path1,path2:path2
    bind_str = ",".join(f"{p}:{p}" for p in binds)
    
    full_cmd = [
        "singularity", "exec",
        "-B", bind_str,
        "--pwd", workdir,
        image
    ] + cmd
    
    result = subprocess.run(full_cmd, capture_output=True, text=True)
    
    # Verbose logging
    if result.stdout:
        print(f"    [STDOUT] {result.stdout.strip()[:500]}")
    
    if result.returncode != 0:
        print(f"    [WARNING] Command returned {result.returncode}")
        if result.stderr:
            print(f"    [STDERR] {result.stderr.strip()[:500]}")
    
    return result.returncode == 0, result.stdout


def calculate_mesh_volume(ply_path):
    """Spočítá objem z PLY mesh souboru."""
    vertices = []
    faces = []
    
    try:
        with open(ply_path, 'rb') as f:
            # Parse header
            vertex_count = 0
            face_count = 0
            format_type = 'ascii'
            vertex_props = []
            
            while True:
                line = f.readline().decode('ascii').strip()
                if line.startswith('format'):
                    format_type = line.split()[1]
                elif line.startswith('element vertex'):
                    vertex_count = int(line.split()[-1])
                elif line.startswith('element face'):
                    face_count = int(line.split()[-1])
                elif line.startswith('property') and vertex_count > 0 and face_count == 0:
                    vertex_props.append(line.split()[1])
                elif line == 'end_header':
                    break
            
            if 'binary' in format_type:
                endian = '<' if 'little' in format_type else '>'
                
                # Vertex size (3 floats minimum, may have more)
                vertex_size = 0
                for prop in vertex_props:
                    if prop in ['float', 'float32']:
                        vertex_size += 4
                    elif prop in ['double', 'float64']:
                        vertex_size += 8
                    elif prop in ['uchar', 'uint8', 'char', 'int8']:
                        vertex_size += 1
                    elif prop in ['int', 'int32', 'uint', 'uint32']:
                        vertex_size += 4
                
                if vertex_size == 0:
                    vertex_size = 12  # Default: 3 floats
                
                for _ in range(vertex_count):
                    data = f.read(vertex_size)
                    if len(data) >= 12:
                        x, y, z = struct.unpack(f'{endian}fff', data[:12])
                        vertices.append([x, y, z])
                
                for _ in range(face_count):
                    count_byte = f.read(1)
                    if count_byte:
                        n = struct.unpack('B', count_byte)[0]
                        indices_data = f.read(n * 4)
                        if len(indices_data) == n * 4:
                            indices = struct.unpack(f'{endian}{n}I', indices_data)
                            faces.append(list(indices))
            else:
                # ASCII
                for _ in range(vertex_count):
                    parts = f.readline().decode('ascii').split()
                    if len(parts) >= 3:
                        vertices.append([float(parts[0]), float(parts[1]), float(parts[2])])
                
                for _ in range(face_count):
                    parts = f.readline().decode('ascii').split()
                    if len(parts) >= 4:
                        n = int(parts[0])
                        faces.append([int(parts[i+1]) for i in range(n)])
        
        if not vertices or not faces:
            return None, None
        
        # Signed tetrahedron volume
        total_volume = 0.0
        total_area = 0.0
        
        for face in faces:
            if len(face) >= 3 and max(face) < len(vertices):
                v0 = vertices[face[0]]
                v1 = vertices[face[1]]
                v2 = vertices[face[2]]
                
                cross = [
                    v1[1]*v2[2] - v1[2]*v2[1],
                    v1[2]*v2[0] - v1[0]*v2[2],
                    v1[0]*v2[1] - v1[1]*v2[0]
                ]
                total_volume += (v0[0]*cross[0] + v0[1]*cross[1] + v0[2]*cross[2]) / 6.0
                
                e1 = [v1[i]-v0[i] for i in range(3)]
                e2 = [v2[i]-v0[i] for i in range(3)]
                cross_area = [
                    e1[1]*e2[2] - e1[2]*e2[1],
                    e1[2]*e2[0] - e1[0]*e2[2],
                    e1[0]*e2[1] - e1[1]*e2[0]
                ]
                total_area += (cross_area[0]**2 + cross_area[1]**2 + cross_area[2]**2)**0.5 / 2.0
        
        return abs(total_volume), total_area
        
    except Exception as e:
        print(f"    Error calculating volume: {e}")
        return None, None


def process_tree(ply_path, output_dir, image_path):
    """Zpracuje jeden strom a vrátí výsledky."""
    basename = Path(ply_path).stem
    
    print(f"\n{'='*60}")
    print(f"Processing: {basename}")
    print(f"{'='*60}")
    
    results = {
        "filename": basename,
        "volume_m3": None,
        "surface_area_m2": None,
        "height_m": None,
        "method": None,
        "success": False
    }
    
    # Cesty k výstupům
    raycloud_ply = output_dir / f"{basename}_raycloud.ply"
    terrain_mesh = output_dir / f"{basename}_raycloud_mesh.ply"
    trees_txt = output_dir / f"{basename}_raycloud_trees.txt"
    tree_mesh = output_dir / f"{basename}_raycloud_trees_mesh.ply"
    
    # Bind paths - input and output dirs
    input_dir = ply_path.parent
    bind_dirs = [str(input_dir.absolute()), str(output_dir.absolute())]
    
    # Krok 1: RayImport
    print("  Step 1: RayImport...")
    success, _ = run_singularity(image_path, [
        "rayimport", str(ply_path.absolute()), "ray", SCANNER_POS
    ], str(output_dir.absolute()), bind_dirs)
    
    # Raycloud by měl být vedle input souboru, přesunout do output
    expected_raycloud = ply_path.parent / f"{basename}_raycloud.ply"
    if expected_raycloud.exists():
        os.rename(expected_raycloud, raycloud_ply)
    
    if not raycloud_ply.exists():
        print("    [ERROR] Raycloud not created")
        return results
    
    print(f"    Created: {raycloud_ply.name}")
    
    # Krok 2: RayExtract Terrain
    print("  Step 2: RayExtract Terrain...")
    run_singularity(image_path, [
        "rayextract", "terrain", str(raycloud_ply.absolute())
    ], str(output_dir.absolute()), bind_dirs)
    
    if not terrain_mesh.exists():
        print("    [WARNING] Terrain mesh not created")
    else:
        print(f"    Created: {terrain_mesh.name}")
    
    # Krok 3: RayExtract Trees
    print("  Step 3: RayExtract Trees...")
    if terrain_mesh.exists():
        run_singularity(image_path, [
            "rayextract", "trees",
            str(raycloud_ply.absolute()),
            str(terrain_mesh.absolute()),
            "--height_min", "1.0",
            "--distance_limit", "0.5",
            "--gravity_factor", "0.5"
        ], str(output_dir.absolute()), bind_dirs)
    
    # Krok 4: Spočítat objem
    print("  Step 4: Calculate Volume...")
    
    # Zkusit trees mesh
    if tree_mesh.exists():
        volume, area = calculate_mesh_volume(tree_mesh)
        if volume:
            results["volume_m3"] = round(volume, 4)
            results["surface_area_m2"] = round(area, 4) if area else None
            results["method"] = "rayextract_trees_mesh"
            results["success"] = True
            print(f"    Volume: {results['volume_m3']:.4f} m³")
    
    # Fallback: raywrap
    if not results["success"]:
        print("    Trying raywrap fallback...")
        run_singularity(image_path, [
            "raywrap", str(raycloud_ply.absolute()), "inwards", "0.5"
        ], str(output_dir.absolute()), bind_dirs)
        
        wrap_mesh = output_dir / f"{basename}_raycloud_mesh.ply"
        if wrap_mesh.exists():
            volume, area = calculate_mesh_volume(wrap_mesh)
            if volume:
                results["volume_m3"] = round(volume, 4)
                results["surface_area_m2"] = round(area, 4) if area else None
                results["method"] = "raywrap_inwards"
                results["success"] = True
                print(f"    Volume (raywrap): {results['volume_m3']:.4f} m³")
    
    # Parsovat trees.txt pro výšku
    if trees_txt.exists():
        try:
            with open(trees_txt, 'r') as f:
                content = f.read()
                lines = [l for l in content.split('\n') if l and not l.startswith('#') and not l.startswith('x,')]
                if lines:
                    # Najít max Z
                    max_z = 0
                    for line in lines:
                        parts = line.split(',')
                        if len(parts) >= 3:
                            z = float(parts[2])
                            if z > max_z:
                                max_z = z
                    results["height_m"] = round(max_z, 2)
        except:
            pass
    
    return results


def main():
    parser = argparse.ArgumentParser(description="Batch RayExtract Volume Calculation")
    parser.add_argument("input_folder", help="Folder with prepared PLY files")
    parser.add_argument("output_folder", help="Output folder for results")
    parser.add_argument("--image", help="Singularity image path", default=SINGULARITY_IMAGE)
    args = parser.parse_args()
    
    input_dir = Path(args.input_folder)
    output_dir = Path(args.output_folder)
    image_path = args.image
    
    # Ověřit image
    if not os.path.exists(image_path):
        # Zkusit v storage
        alt_path = f"/storage/brno2/home/{os.environ.get('USER', 'tomea')}/RCT/img/{image_path}"
        if os.path.exists(alt_path):
            image_path = alt_path
        else:
            print(f"ERROR: Singularity image not found: {image_path}")
            return
    
    print(f"Using image: {image_path}")
    
    # Vytvořit output
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Najít PLY soubory
    ply_files = list(input_dir.glob("*.ply"))
    
    if not ply_files:
        print(f"No PLY files found in {input_dir}")
        return
    
    print(f"Found {len(ply_files)} PLY files")
    print("="*60)
    
    all_results = []
    
    for ply_file in ply_files:
        results = process_tree(ply_file, output_dir, image_path)
        all_results.append(results)
    
    # Uložit výsledky
    summary_file = output_dir / "volume_results.json"
    with open(summary_file, "w") as f:
        json.dump(all_results, f, indent=2)
    
    # CSV export
    csv_file = output_dir / "volume_results.csv"
    with open(csv_file, "w") as f:
        f.write("filename,volume_m3,surface_area_m2,height_m,method\n")
        for r in all_results:
            f.write(f"{r['filename']},{r['volume_m3'] or ''},{r['surface_area_m2'] or ''},{r['height_m'] or ''},{r['method'] or ''}\n")
    
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    
    success_count = sum(1 for r in all_results if r["success"])
    print(f"Processed: {len(all_results)} files")
    print(f"Successful: {success_count}")
    print(f"Results: {summary_file}")
    print(f"CSV: {csv_file}")
    
    # Zobrazit výsledky
    print("\nResults:")
    for r in all_results:
        status = "✓" if r["success"] else "✗"
        vol = f"{r['volume_m3']:.2f} m³" if r["volume_m3"] else "N/A"
        print(f"  {status} {r['filename']}: {vol}")


if __name__ == "__main__":
    main()
