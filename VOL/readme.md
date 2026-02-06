# RCT Volume Workflow

Tento adresář obsahuje skripty pro dodatečný výpočet objemu (Volume) z již segmentovaných a vyčištěných stromů (LAZ soubory).

## Požadavky

*   Vstupní data: Adresář obsahující `.laz` soubory jednotlivých stromů (např. `vycistene_stromy/tree_1.laz`, `tree_2.laz`...).
*   (Volitelné) Trajektorie: Pokud máte soubory trajektorie, pojmenujte je stejně jako laz (např. `tree_1.txt`) a nahrajte je do stejné složky, skript je automaticky najde.

## Použití

Spusťte úlohu pomocí `qsub` (podobně jako původní skript), ale jako `SOURCE_DATA` uveďte název složky s vašimi stromy.

Příklad:
```bash
# Nastavení proměnných
export DATADIR=/storage/plzen1/home/vas_user/data_projekt
export SOURCE_DATA=vycistene_stromy  # Jméno složky v DATADIR

# Spuštění
qsub -l select=1:ncpus=4:mem=16gb:scratch_local=20gb -l walltime=04:00:00 -v DATADIR,SOURCE_DATA -- /cesta/k/Volume_Workflow/master_volume.sh
```

## Výstup

Výsledkem bude ZIP soubor `Volume_Results_....zip` v `DATADIR`, který obsahuje:
1.  `volume_report.csv` - Souhrnná tabulka (pokud se podaří extrahovat čísla).
2.  `*_info.txt` - Detailní výstupy z `treeinfo` pro každý strom.
3.  `*_mesh.ply` - Vymodelované meshe (povrchy) stromů (pro vizualizaci).
