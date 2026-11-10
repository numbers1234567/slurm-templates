#!/bin/bash
# Designed for tracing running details for R&D projects that are iterated on rapidly, focused on conda environments
#  1. Clones a specified branch from a specified repo
#  2. Installs as a new python library in an existing conda env
#  3. Creates a new directory with the git hash (If it doesn't exist. If it exists, just uses goes into the same dir)
#  4. Records environment details
#  5. Runs the script
#
# Step 3 goes into the same dir in case of requeue or continuing from a previous run, but this behavior can be changed easily.

#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task [CPUS_CONFIG]
#SBATCH --time [TIME_CONFIG]
#SBATCH --partition [PARTITION_CONFIG]
#SBATCH --gres [GPU_CONFIG]
#SBATCH --mem [MEM_CONFIG]
#SBATCH --job-name [PROJECT_NAME]
#SBATCH --requeue [optional]

#SBATCH --output=logs/job-%j.out

set -eo pipefail
source ~/.bashrc

RUNDIR="$PWD"
cd "$RUNDIR"

BRANCH="${BRANCH:-main}"
REPO_URL="[REPO_URL]"
PROJECT_NAME="[PROJECT_NAME]"
JOB_SCRIPT="${JOB_SCRIPT:-$0}"
JOB_SCRIPT="$(realpath "$JOB_SCRIPT")"
RUNNER_CONDA_ENV="[RUNNER_CONDA_ENV_PATH]"

# Keep system SSH from loading incompatible libraries inherited from Conda/modules.
export GIT_SSH_COMMAND="env -u LD_LIBRARY_PATH -u LD_PRELOAD /usr/bin/ssh"

# Resolve the branch without cloning so existing runs can be reused.
REMOTE_REF="$(git ls-remote --exit-code "$REPO_URL" "refs/heads/$BRANCH")"
COMMIT="${REMOTE_REF%%[[:space:]]*}"
LOGDIR="$RUNDIR/$COMMIT"

CLONE_TMP=""
cleanup() {
    if [[ -n "$CLONE_TMP" ]]; then
        rm -rf -- "$CLONE_TMP"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -d "$LOGDIR" ]]; then
    CLONE_TMP="$(mktemp -d "$RUNDIR/.$PROJECT_NAME-clone.XXXXXX")"
    git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$CLONE_TMP/$PROJECT_NAME"
    # Use the resolved commit even if the branch advanced during cloning.
    git -C "$CLONE_TMP/$PROJECT_NAME" checkout --detach "$COMMIT"
    # Publish the complete checkout; an interrupted clone leaves no run directory.
    mv -T -- "$CLONE_TMP" "$LOGDIR"
    CLONE_TMP=""
fi

cp -- "$JOB_SCRIPT" "$LOGDIR/$(basename "$JOB_SCRIPT")"
cd "$LOGDIR"

### Set up the runtime environment after Git operations.
module load miniconda
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$RUNNER_CONDA_ENV"

cd $PROJECT_NAME
pip install -e .

# Record environment details
pip freeze > ../env.txt
nvidia-smi > ../cuda.txt
conda info > ../conda.txt

### Run
python run.py &> log.txt
