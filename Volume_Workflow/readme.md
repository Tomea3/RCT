# RayExtract Volume Workflow

Batch výpočet objemu stromů z TLS point cloud dat pomocí RayCloudTools.

## Požadavky

### Windows
```bash
pip install laspy numpy open3d
```

### Metacentrum
- Singularity image: `raycloudtools.img`

## Použití

### 1. Příprava dat (Windows)

```bash
python prepare_trees.py input_laz_folder output_ply_folder [--plane plane.laz]
```

- Načte LAZ soubory stromů
- Přidá umělou zem (nebo použije plane.laz)
- Spočítá normály směrem ke skeneru
- Uloží jako binární PLY

### 2. Zpracování (Metacentrum)

```bash
# Zkopírovat PLY soubory na storage
scp output_ply_folder/*.ply tomea@skirit.metacentrum.cz:/storage/brno2/home/tomea/trees/

# Interaktivní job
qsub -I -l select=1:ncpus=4:mem=8gb:scratch_local=20gb -l walltime=4:00:00

cd $SCRATCHDIR
cp /storage/brno2/home/tomea/trees/*.ply input/
cp /storage/brno2/home/tomea/RCT/img/raycloudtools.img .
cp /storage/brno2/home/tomea/RCT/Volume_Workflow/process_volumes.py .

python3 process_volumes.py input/ results/
```

### 3. Výstup

- `volume_results.json` - detailní výsledky
- `volume_results.csv` - tabulka pro Excel

## Soubory

| Soubor | Popis |
|--------|-------|
| `prepare_trees.py` | Windows: příprava LAZ → PLY |
| `process_volumes.py` | Metacentrum: batch výpočet objemu |
| `rayextract_workflow.txt` | Manuální postup krok za krokem |

## Reference

- [RayCloudTools](https://github.com/csiro-robotics/raycloudtools)
- [TreeTools](https://github.com/csiro-robotics/treetools)
