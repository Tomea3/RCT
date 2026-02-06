# setup sublime: https://www.geeksforgeeks.org/how-to-use-terminal-in-sublime-text-editor/
alt + 1
@


## Example command
```
qsub -l select=1:ncpus=16:mem=64gb:scratch_local=25gb -l walltime=12:00:00 -- /storage/projects2/InterCOST/segment.sh SOURCE_DATA DATADIR VOXELIZE VOXEL_RES ADD_TIME
```

# set variables
```
export SOURCE_DATA=rudice_sample.laz
export DATADIR=/storage/plzen1/home/krucek/test_dir
export VOXELIZE=${3:-true}
export VOXEL_RES=${4:-0.01}
export ADD_TIME=${5:-true}
```


```
qsub -l select=1:ncpus=1:mem=200gb:scratch_local=500gb -l walltime=24:00:00 -- /storage/brno2/home/tomea/RCT/segment.sh Lanzhot_02_subsampled_cut_heart.laz /storage/brno2/home/tomea/RCT/DATA_LAZ false 0.02 false
```

```
qsub -l select=1:ncpus=24:mem=64gb:scratch_local=150gb -l walltime=12:00:00 -- /storage/plzen1/home/krucek/scripts/segment.sh 07_test.laz /storage/plzen1/home/krucek/data/rz_0005 true 0.02 true
qsub -l select=1:ncpus=24:mem=128gb:scratch_local=300gb -l walltime=12:00:00 -- /storage/plzen1/home/krucek/scripts/segment.sh 07_clipped.laz /storage/plzen1/home/krucek/data/rz_0005 true 0.02 true

```

qsub -l select=1:ncpus=24:mem=128gb:scratch_local=300gb -l walltime=12:00:00 -- /storage/plzen1/home/krucek/scripts/segment.sh Michovky_mls.laz /storage/plzen1/home/krucek/data/michovky false 0.02 false Michovky1_01_traj.txt

qsub -l select=1:ncpus=48:mem=256gb:scratch_local=300gb -l walltime=24:00:00 -- /storage/plzen1/home/krucek/scripts/segment.sh Michovky_uls.laz /storage/plzen1/home/krucek/data/michovky false 0.02 false Michovky1_01_traj.txt
