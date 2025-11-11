#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- 1. Auto-Detection and Relaunch (if needed) ---

# Get the machine's hardware architecture
NATIVE_ARCH=$(uname -m)

# Check if we are on Apple Silicon (arm64) AND we have NOT already relaunched.
# "__INTERNAL_X86_RUN__" is a special flag we add to avoid an infinite loop.
if [ "$NATIVE_ARCH" == "arm64" ] && [ "$1" != "__INTERNAL_X86_RUN__" ]; then
    
    # --- Silicon Gatekeeper ---
    # This block only runs ONCE on an arm64 machine.
    # It checks for dependencies and then re-runs this *entire* script
    # using the 'arch -x86_64' emulator.
    
    echo "--- Apple Silicon (arm64) hardware detected. ---"
    
    # Check for the required x86_64 Miniconda installation
    CONDA_ACTIVATE_SCRIPT="$HOME/miniconda3-x86_64/bin/activate"
    if [ ! -f "$CONDA_ACTIVATE_SCRIPT" ]; then
        echo "--- ERROR: x86_64 Miniconda for Rosetta not found. ---" >&2
        echo "This script requires an emulated x86_64 Miniconda install to run on Apple Silicon." >&2
        echo "Please install it in: $HOME/miniconda3-x86_64" >&2
        exit 1
    fi
    
    # Check that the user provided the correct arguments
    if [ "$#" -ne 2 ]; then
        echo "Usage: $0 <BioProjectID> <ProjectName>"
        echo "Example: $0 PRJNA123456 my_gvhd_study"
        exit 1
    fi

    echo "--- Relaunching script under x86_64 emulation (Rosetta 2)... ---"
    
    # Relaunch this script.
    # We pass the special "__INTERNAL_X86_RUN__" flag as $1
    # and pass the user's original arguments ($1 and $2) after it.
    # 'zsh' is used as you specified, but 'bash' would also work.
    arch -x86_64 zsh $0 "__INTERNAL_X86_RUN__" "$1" "$2"
    
    # Exit the original (arm64) script. The relaunched script's exit code
    # will be passed up.
    exit $?
fi

# --- End of Auto-Detection ---

#
# If the script gets to this point, it is GUARANTEED to be running
# in an x86_64 environment (either natively on Intel, or emulated on Silicon).
#

echo "--- Script now executing in x86_64 mode. ---"

# --- 2. Argument and Environment Setup ---

# We now handle the arguments based on how the script was run
if [ "$1" == "__INTERNAL_X86_RUN__" ]; then
    # --- Emulated Silicon Setup ---
    echo "--- Activating emulated (x86_64) conda environment... ---"
    
    # $1 is "__INTERNAL_X86_RUN__", $2 is BioProjectID, $3 is ProjectName
    shift # Removes the special flag
    BIOPROJECT_ID="$1"
    PROJECT_NAME="$2"
    
    # Source the emulated conda environment
    source "$HOME/miniconda3-x86_64/bin/activate" sra-env
    
else
    # --- Native Intel / HPC Setup ---
    echo "--- Activating native (intel) conda environment... ---"
    
    # Check arguments for native run
    if [ "$#" -ne 2 ]; then
        echo "Usage: $0 <BioProjectID> <ProjectName>"
        echo "Example: $0 PRJNA123456 my_gvhd_study"
        exit 1
    fi
    
    BIOPROJECT_ID="$1"
    PROJECT_NAME="$2"
    
    # Source the standard/native conda environment
    # This assumes 'conda' is in your PATH.
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate sra-env
fi

# --- 3. Tool Check ---
if ! command -v esearch &> /dev/null; then
    echo "Error: 'esearch' (from SRA-Toolkit) not found." >&2
    echo "Please ensure the 'sra-env' environment is set up correctly with entrez-direct." >&2
    conda deactivate
    exit 1
fi
echo "--- Environment activated, 'esearch' found. ---"

# --- 4. Paths ---
BASE_DIR=$(pwd) # The directory where you ran the script
RAW_DATA_DIR="${BASE_DIR}/raw_data/${PROJECT_NAME}"
ARTIFACT_DIR="${BASE_DIR}/qiime2_artifacts"
MANIFEST_PATH="${ARTIFACT_DIR}/${PROJECT_NAME}_manifest.tsv"

echo "--- 5. Setting up directories ---"
mkdir -p "$RAW_DATA_DIR"
mkdir -p "$ARTIFACT_DIR"
echo "Data will be downloaded to: $RAW_DATA_DIR"

# --- 6. Fetching SRA accessions ---
echo "--- Step 6: Fetching SRA accessions for $BIOPROJECT_ID ---"
esearch -db sra -query "$BIOPROJECT_ID" \
  | efetch -format runinfo \
  | cut -d ',' -f 1 \
  | grep "^SRR" \
  > "${RAW_DATA_DIR}/run_accessions.txt"

ACCESSIONS_COUNT=$(wc -l < "${RAW_DATA_DIR}/run_accessions.txt")
if [ "$ACCESSIONS_COUNT" -eq 0 ]; then
    echo "Error: No SRR accessions found for $BIOPROJECT_ID." >&2
    conda deactivate
    exit 1
fi
echo "Found $ACCESSIONS_COUNT accessions."

# --- 7. Download and Convert FASTQ ---
echo "--- Step 7: Downloading & converting to FASTQ ---"
echo "Changing to directory: $RAW_DATA_DIR"
cd "$RAW_DATA_DIR" # Run the downloads *inside* the data directory

echo "Running prefetch..."
# Use --max-size 100G as a safety, adjust as needed
prefetch --max-size 100G --option-file run_accessions.txt

echo "Running fasterq-dump..."
cat run_accessions.txt | while read srr; do
    echo "Processing $srr"
    # --split-files for paired-end, --progress for updates
    fasterq-dump --split-files --progress "$srr"
done

# --- 8. Creating Manifest ---
echo "--- Step 8: Creating manifest file... ---"
# We are still inside $RAW_DATA_DIR

# Create the header for the manifest
echo -e "sample-id\tabsolute-filepath-fwd\tabsolute-filepath-rev" > "manifest.tmp"

# Find all forward reads (_1.fastq) and build the manifest from them
for f_fwd in *_1.fastq; do
    # Get the sample ID by removing '_1.fastq' from the filename
    SAMPLE_ID=$(basename "$f_fwd" _1.fastq)
    
    # Define the matching reverse read
    f_rev="${SAMPLE_ID}_2.fastq"
    
    # Get the full, absolute paths
    abs_fwd="$(pwd)/$f_fwd"
    abs_rev="$(pwd)/$f_rev"
    
    # Check if the reverse file exists (for paired-end data)
    if [ -f "$f_rev" ]; then
        echo -e "$SAMPLE_ID\t$abs_fwd\t$abs_rev" >> "manifest.tmp"
    else
        echo "Warning: No reverse read ($f_rev) found for $SAMPLE_ID. Skipping." >&2
    fi
done

if [ ! -s "manifest.tmp" ] || [ $(wc -l < "manifest.tmp") -eq 1 ]; then
    echo "Error: Manifest was not created or no FASTQ pairs were found." >&2
    cd "$BASE_DIR"
    conda deactivate
    exit 1
fi

# Move the final manifest to the artifacts directory
mv "manifest.tmp" "$MANIFEST_PATH"
echo "Manifest created at: $MANIFEST_PATH"

# --- 9. Cleanup ---
echo "--- Step 9: Deactivating environment ---"
cd "$BASE_DIR" # Go back to the original directory
conda deactivate
echo "--- Data fetching complete. ---"