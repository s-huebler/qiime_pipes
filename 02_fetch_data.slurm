#!/bin/bash

# --- 1. SLURM Directives (The "Work Order") ---
#
# Use the $SLURM_ACCOUNT variable, or default to 'default_account' if not set
#SBATCH --account=guo
#
# Use the $SLURM_PARTITION variable, or default to 'general' if not set
#SBATCH --partition=kingspeak-shared
#
# Use the $SLURM_MAIL_USER variable, or default to yourself (as a fallback)
#SBATCH --mail-user=$SLURM_MAIL_USER
#
#SBATCH --job-name=download_sra    # Job name
#SBATCH --output=slurm_out/fetch_%j.out # Standard output log
#SBATCH --error=slurm_out/fetch_%j.err  # Standard error log
#SBATCH --time=08:00:00            # Max time (2 hours). Adjust as needed.
#SBATCH --nodes=1                  # Run on a single node
#SBATCH --ntasks=1                 # Run one task
#SBATCH --cpus-per-task=8          # Request 8 CPUs (for fasterq-dump)
#SBATCH --mem=16G                  # Request 16GB of memory
#SBATCH --mail-type=END,FAIL       # Send email on job END or FAIL

# --- 2. The Script (The "Recipe") ---
set -e # Exit immediately if a command fails

# --- Setup ---
echo "--- Starting SRA download job ---"
echo "Job ID: $SLURM_JOB_ID"
echo "Running on host: $(hostname)"

# Create the directory for Slurm logs (if it doesn't exist)
mkdir -p slurm_out

# Check for the ProjectName argument
if [ "$#" -ne 1 ]; then
    echo "Usage: sbatch 02_fetch_data.slurm <ProjectName>"
    exit 1
fi

PROJECT_NAME="$1"

# --- Load HPC Modules ---
# Purge any modules you might have loaded
module purge 

# Load the SRA Toolkit module
module load sra-toolkit/3.1.1 

echo "--- Modules loaded. ---"
command -v prefetch       # Verify prefetch is found
command -v fasterq-dump   # Verify fasterq-dump is found

# --- Define Paths ---
# Assumes you run 'sbatch' from your project's base directory
BASE_DIR=$(pwd)
RAW_DATA_DIR="${BASE_DIR}/raw_data/${PROJECT_NAME}"
ARTIFACT_DIR="${BASE_DIR}/qiime2_artifacts/${PROJECT_NAME}"

# Create directories if it doesn't exist
mkdir -p "$RAW_DATA_DIR"
mkdir -p "$ARTIFACT_DIR"

#MANIFEST_PATH="${RAW_DATA_DIR}/manifest.tsv"
ACCESSION_FILE="${RAW_DATA_DIR}/run_accessions.txt"

# --- Pre-run Check ---
# Check if the accession file exists
if [ ! -f "$ACCESSION_FILE" ]; then
    echo "Error: Accession file not found at: $ACCESSION_FILE" >&2
    echo "Please run the '01_fetch_accessions.sh' script locally first." >&2
    exit 1
fi



# --- 7. Download and Convert FASTQ ---
echo "--- Step 7: Downloading & converting to FASTQ ---"
echo "Changing to directory: $RAW_DATA_DIR"
cd "$RAW_DATA_DIR"

echo "Running prefetch..."
# Use --max-size 100G as a safety, adjust as needed
prefetch --max-size 100G --option-file run_accessions.txt

echo "Running fasterq-dump..."
# We pipe the accessions to fasterq-dump.
# We also use the $SLURM_CPUS_PER_TASK variable to tell
# fasterq-dump how many CPUs we requested from Slurm.
cat run_accessions.txt | while read srr; do
    echo "Processing $srr"
    fasterq-dump \
      --split-files \
      --progress \
      --threads $SLURM_CPUS_PER_TASK \
      "$srr"
done
echo "--- fasterq-dump complete. ---"

# --- 8. Creating Manifest ---
echo "--- Step 8: Creating manifest file... ---"
# We are still inside $RAW_DATA_DIR



# Create the header, overwriting any existing manifest.tsv
echo -e "sample-id\tforward-absolute-filepath\treverse-absolute-filepath" > manifest.tsv

# Loop through all files ending in _1.fastq in the current directory
for f in *_1.fastq; do
  # Define the corresponding reverse read filename by replacing _1 with _2
  r="${f/_1.fastq/_2.fastq}"
  
  # Check if both the forward file ($f) and the reverse file ($r) exist
  if [ -f "$f" ] && [ -f "$r" ]; then
    # If both exist, define the sample ID by removing _1.fastq
    id="${f/_1.fastq/}"
    
    # Append the sample information to manifest.tsv
    # Using $CWD ensures we get the full, absolute path
    echo -e "$id\t${CWD}/$f\t${CWD}/$r" >> manifest.tsv
  else
    # Optional: Log a warning for skipped files
    echo "Warning: Skipping ${f/_1.fastq/} because one or both read files are missing." >&2
  fi
done

# Create the header
#echo -e "sample-id\tabsolute-filepath-fwd\tabsolute-filepath-rev" > "manifest.tsv"
#
# Find all forward reads (_1.fastq) and build the manifest
#for f_fwd in *_1.fastq; do
#    SAMPLE_ID=$(basename "$f_fwd" _1.fastq)
#   f_rev="${SAMPLE_ID}_2.fastq"
#    
#    abs_fwd="$(pwd)/$f_fwd"
#    abs_rev="$(pwd)/$f_rev"
#    
#    if [ -f "$f_rev" ]; then
#        echo -e "$SAMPLE_ID\t$abs_fwd\t$abs_rev" >> "manifest.tsv"
#    else
#        echo "Warning: No reverse read ($f_rev) found for $SAMPLE_ID. Skipping." >&2
#    fi
#done

# Check that the manifest was created successfully
if [ ! -s "manifest.tsv" ] || [ $(wc -l < "manifest.tsv") -eq 1 ]; then
    echo "Error: Manifest was not created or no FASTQ pairs were found." >&2
    cd "$BASE_DIR"
    exit 1
fi

# Move the final manifest to the artifacts directory
#mv "manifest.tsv" "$MANIFEST_PATH"
#echo "Manifest created at: $MANIFEST_PATH"

# --- 9. Cleanup ---
echo "--- Step 9: Returning to base directory. ---"
cd "$BASE_DIR"
echo "--- Slurm job complete. ---"
