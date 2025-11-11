# qiime_pipes
This repository contains scripts to fetch SRA data and submit processing jobs to the University of Utah CHPC. 

## Locate data with 01_fetch_accesions.sh

### Set up:
Download this script and make executable (chmod +x 01_fetch_accessions.sh)

Requirements:
- Requires miniconda environment named sra-env with e-direct installed.
  - This script is designed for apple architecture. If using apple silicon make sure to have Rosetta 2 emulation enabled with miniconda3-x86_64 installed.

### Use: 


Run 01_fetch_accessions.sh locally to download accession text file from a specified Bioproject.

Input:
- [1] BIOPROJECT_ID: Bioproject accession number
- [2] PROJECT_NAME: Name of subdirectory to hold results for this project
  
Output: [PROJECT_NAME]/run_accessions.txt

Example: ./01_fetch_accessions.sh PRJNA724885 PRJNA724885_Moraes2024

## HPC Setup (One-Time Only)

Before you can run the `02_download_and_manifest.slurm` script, you must set three environment variables on your HPC's login node. This tells Slurm your account, partition, and email.

1.  Open your `.bashrc` file for editing:
    ```bash
    nano ~/.bashrc
    ```
2.  Add the following lines to the very bottom of the file. **Replace the values** with your specific details:

    ```bash
    # --- SLURM DEFAULTS ---
    # Your project/lab account (find with 'sshare -u $USER')
    export SLURM_ACCOUNT="your_account_name"
    
    # The partition you want to use (find with 'sinfo')
    export SLURM_PARTITION="your_partition_name"
    
    # Your email address for job notifications
    export SLURM_MAIL_USER="your_email@university.edu"
    ```

3.  Save the file and exit `nano` (Press `Ctrl+O` to write, `Ctrl+X` to exit).

4.  "Source" the file to make the changes active in your current session:
    ```bash
    source ~/.bashrc
    ```

That's it! Now, any time you log in, these variables will be set automatically, and the `sbatch` script will use them.

## Usage

1.  **Local (Step 1):**
    ```bash
    ./01_fetch_accessions.sh <BioProjectID> <ProjectName>
    ```

2.  **Sync to HPC (Step 2):**
    `git push` / `git pull` to sync the new `run_accessions.txt` file.

3.  **HPC (Step 3):**
    ```bash
    sbatch 02_download_and_manifest.slurm <ProjectName>
    ```


 

