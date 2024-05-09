#!/bin/bash
#
#SBATCH --cluster=faculty
#SBATCH --qos=adamw
#SBATCH --partition=adamw
#SBATCH --job-name "EMMA model slurm_verbose.sbatch"
#SBATCH --nodes=1
#SBATCH --ntasks=16
#SBATCH --mem=160G
#SBATCH  -C INTEL
#SBATCH --time=240:00:00
#SBATCH --mail-user=adamw@buffalo.edu
#SBATCH --mail-type=begin
#SBATCH --mail-type=end
#SBATCH -o emma_model_verbose.out


# Specify directories needed and sif file
export PROJECT_FOLDER="/projects/academic/adamw/users/$USER/"
export APPTAINER_CACHEDIR="/scratch/"$USER"/apptainer"
export SIF_PATH=$PROJECT_FOLDER"/apptainer"
export SIF_FILE="AdamWilsonLab-emma_docker-latest.sif"
export APPTAINER_CACHEDIR="/panasas/scratch/grp-adamw/"$USER"/apptainer"
export EMMA_HOME=$PROJECT_FOLDER"/users/"$USER"/emma_model"

# set singularity cache and tmp directories to the same as apptainer
# needed because CCR is still using singularity and it will use these directories
export SINGULARITY_CACHEDIR=$APPTAINER_CACHEDIR
export SINGULARITY_TMPDIR=$APPTAINER_TMPDIR
export SINGULARITY_LOCALCACHEDIR=$APPTAINER_LOCALCACHEDIR


echo "exporting directories"

# make needed directories

echo "making directories"

mkdir -p "$APPTAINER_CACHEDIR/tmp"
mkdir -p "$APPTAINER_CACHEDIR/run"

# execute the function run_verbose.sh (which in turn runs the function run.R, which in turn calls tar_make())

echo "executing run_verbose.sh"

  singularity exec \
  --bind $PROJECT_FOLDER:$PROJECT_FOLDER \
  --bind $APPTAINER_CACHEDIR/tmp:/tmp \
  --bind $APPTAINER_CACHEDIR/run:/run \
  --home $EMMA_HOME \
  $SIF_PATH/$SIF_FILE ./run_verbose.sh
