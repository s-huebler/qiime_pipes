#!/bin/bash
#SBATCH --job-name=qiime2_import
#SBATCH --account=guo
#SBATCH --partition=kingspeak-shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00                 # 1 hour should be enough
#SBATCH --output=slurm_out/import_%j.out # Standard output log
#SBATCH --error=slurm_out/import_%j.err  # Standard error log

set -e

# --- 1. Config ---
if [ "$#" -ne 1 ]; then
    echo "Usage: sbatch $0 <ProjectName>"
    exit 1
fi
PROJECT_NAME="$1"

# --- 2. Environment ---
echo "Loading QIIME 2..."
# This is HPC-specific. Adjust as needed.
# Option 1: Conda
#source "$(conda info --base)/etc/profile.d/conda.sh"
#conda activate qiime2-env-name # <-- TODO: Change to your QIIME 2 env name

# Option 2: Module Load (example)
module load anaconda3/2023.03
module load qiime2/2023.5

# --- 3. Paths ---
BASE_DIR=$(pwd) # Assumes sbatch is run from project root
MANIFEST_PATH="${BASE_DIR}//raw_data/${PROJECT_NAME}/manifest.tsv"
OUTPUT_DIR="${BASE_DIR}/qiime2_artifacts/${PROJECT_NAME}"
DEMUX_QZA="${OUTPUT_DIR}/demux_seqs.qza"
DEMUX_QZV="${OUTPUT_DIR}/demux_seqs_viz.qzv"

mkdir -p "$OUTPUT_DIR"

# --- 4. Run Import and Visualization ---
echo "Importing data..."
qiime tools import \
  --type 'SampleData[PairedEndSequencesWithQuality]' \
  --input-path "$MANIFEST_PATH" \
  --output-path "$DEMUX_QZA" \
  --input-format PairedEndFastqManifestPhred33V2

echo "Visualizing demuxed sequences..."
qiime demux summarize \
  --i-data "$DEMUX_QZA" \
  --o-visualization "$DEMUX_QZV"

echo "---"
echo "Job Complete."

