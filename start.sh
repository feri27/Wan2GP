#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "Container started. Running custom start.sh script..." >&2 # Redirect to stderr
echo "Timestamp: $(date)" >&2 # Redirect to stderr

# --- SSH Setup (Required for Full SSH/SCP/SFTP) ---
# This block sets up the SSH daemon for the root user.
# openssh-server is already installed via the Dockerfile.
echo "Setting up SSH daemon..." >&2 # Redirect to stderr

# Create the .ssh directory for the root user if it doesn't exist
mkdir -p /root/.ssh
# Set correct permissions for the .ssh directory (owner read/write/execute, others no access)
chmod 700 /root/.ssh

# RunPod injects the public key from your user settings into the $PUBLIC_KEY environment variable.
# Append this key to the authorized_keys file for the root user.
# This allows key-based SSH authentication.
echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
# Set correct permissions for the authorized_keys file (owner read/write, others no access).
# The RunPod guide shows 700, but 600 is standard and more secure for authorized_keys.
chmod 600 /root/.ssh/authorized_keys

# Start the SSH service
service ssh start
echo "SSH daemon started." >&2 # Redirect to stderr
# --- End SSH Setup ---

# --- Activate Python Environment ---
echo "Using Python from base PyTorch image (Conda environment)." >&2 # Redirect to stderr

# --- Environment Sanity Checks ---
echo "--- Environment Checks ---" >&2 # Redirect to stderr
echo "User: $(whoami)" >&2 # Redirect to stderr
echo "Workdir: $(pwd)" >&2 # Redirect to stderr
echo "Python version: $(python --version)" >&2 # Redirect to stderr
echo "PyTorch version: $(python -c 'import torch; print(torch.__version__)')" >&2 # Redirect to stderr
echo "CUDA available: $(python -c 'import torch; print(torch.cuda.is_available())')" >&2 # Redirect to stderr
if python -c 'import torch; exit(not torch.cuda.is_available())'; then
    echo "CUDA device count: $(python -c 'import torch; print(torch.cuda.device_count())')" >&2 # Redirect to stderr
    if [ "$(python -c 'import torch; print(torch.cuda.device_count())')" -gt "0" ]; then
      echo "Current CUDA device: $(python -c 'import torch; print(torch.cuda.current_device())')" >&2 # Redirect to stderr
      echo "Device name: $(python -c 'import torch; print(torch.cuda.get_device_name(torch.cuda.current_device()))')" >&2 # Redirect to stderr
    fi
else
    echo "WARNING: PyTorch cannot find CUDA. Check GPU drivers, Docker runtime, and base image." >&2 # Redirect to stderr
fi
echo "NVIDIA SMI:" >&2 # Redirect to stderr
nvidia-smi 2>&1 || echo "nvidia-smi command not found or failed." >&2 # Redirect nvidia-smi output and error to stderr
echo "------------------------" >&2 # Redirect to stderr

# --- Define Key Application Paths (these are the paths wgp.py expects or that we will manage) ---
APP_BASE_DIR="/app"
APP_CKPTS_DIR="${APP_BASE_DIR}/ckpts"
APP_OUTPUTS_DIR="${APP_BASE_DIR}/outputs" # wgp.py writes here by default
APP_SETTINGS_DIR="${APP_BASE_DIR}/settings"
APP_LORAS_DIR="${APP_BASE_DIR}/loras" # Central LoRA directory

# Specific LoRA type paths that wgp.py might expect (these will be symlinked to APP_LORAS_DIR)
APP_LORAS_HUNYUAN_DIR="${APP_BASE_DIR}/loras_hunyuan"
APP_LORAS_HUNYUAN_I2V_DIR="${APP_BASE_DIR}/loras_hunyuan_i2v"
APP_LORAS_I2V_DIR="${APP_BASE_DIR}/loras_i2v"
APP_LORAS_LTXV_DIR="${APP_BASE_DIR}/loras_ltxv"

# Helper function to handle symlinking a managed directory with a mountpoint check
# and auto-creation of the W2GP_ specified path if it doesn't exist.
# Usage: handle_managed_dir TARGET_APP_PATH W2GP_ENV_VAR_VALUE W2GP_ENV_VAR_NAME
handle_managed_dir() {
    local target_dir="$1" # e.g., /app/loras (the path inside /app)
    local w2gp_value="$2" # e.g., value of $W2GP_LORAS (can be empty, e.g. /workspace/Wan2GP/Loras)
    local w2gp_name="$3"  # e.g., "W2GP_LORAS"

    if [ -n "$w2gp_value" ]; then # If the W2GP_ environment variable is set
        echo "${w2gp_name} is set to '$w2gp_value'." >&2 # Redirect to stderr

        # Check if the directory specified by w2gp_value exists, and create it if it doesn't.
        # This applies to the path on the persistent volume (e.g., /workspace/Wan2GP/Loras)
        if [ ! -d "$w2gp_value" ]; then
            echo "Directory '$w2gp_value' for ${w2gp_name} does not exist. Creating it..." >&2 # Redirect to stderr
            mkdir -p "$w2gp_value"
            if [ $? -eq 0 ]; then
                echo "Successfully created directory '$w2gp_value'." >&2 # Redirect to stderr
            else
                echo "ERROR: Failed to create directory '$w2gp_value'. Please check permissions and path." >&2 # Redirect to stderr
                # Decide if you want to exit or continue with a broken symlink
                # exit 1 # Or just let it proceed to create a broken symlink
            fi
        else
            echo "Directory '$w2gp_value' for ${w2gp_name} already exists." >&2 # Redirect to stderr
        fi

        is_mountpoint=false
        # Check if target_dir (e.g. /app/loras) is a mount point.
        # This detects if the user did a direct docker bind mount to /app/loras
        if command -v mountpoint >/dev/null && mountpoint -q "$target_dir"; then
            is_mountpoint=true
        fi

        if $is_mountpoint; then
            echo "INFO: ${target_dir} is a direct bind mount." >&2 # Redirect to stderr
            echo "      The ${w2gp_name} environment variable ('$w2gp_value') will be IGNORED for symlinking ${target_dir}." >&2 # Redirect to stderr
            echo "      The direct bind mount for ${target_dir} will be used." >&2 # Redirect to stderr
            # Even if it's a mountpoint, the w2gp_value directory (e.g. /workspace/Wan2GP/Loras)
            # might still be useful if other logic in the app or user setup relies on it.
            # The creation logic above ensures it exists if specified.
        else
            echo "Symlinking ${target_dir} to '$w2gp_value'..." >&2 # Redirect to stderr
            # This rm -rf removes the content from the image layer (e.g., README.txt in /app/loras)
            # to allow the path itself to become a symlink.
            rm -rf "${target_dir}"
            ln -s "$w2gp_value" "${target_dir}"
            echo "Symlinked ${target_dir} -> $w2gp_value" >&2 # Redirect to stderr
        fi
    else
        # W2GP_ variable is not set for this path
        echo "${w2gp_name} is not set." >&2 # Redirect to stderr
        # Special handling for APP_LORAS_DIR: ensure it exists if W2GP_LORAS is not set,
        # because other LoRA directories will be symlinked to it.
        # This is safe even if APP_LORAS_DIR is a direct bind mount (mkdir -p won't delete content).
        if [ "$target_dir" == "${APP_LORAS_DIR}" ]; then
            echo "Ensuring default ${target_dir} directory exists (for LoRA symlink targets)." >&2 # Redirect to stderr
            mkdir -p "${target_dir}"
        else
            # For ckpts, settings, outputs: if W2GP_ var is not set, assume git pull or app handles them,
            # or it's a direct bind mount.
            echo "Assuming ${target_dir} is populated by git pull, app, or is a direct bind mount." >&2 # Redirect to stderr
        fi
    fi
}

echo "--- Configuring Application Directories and LoRA Symlinks ---" >&2 # Redirect to stderr

# 1. Handle W2GP_LORAS, W2GP_MODELS, W2GP_SETTINGS, W2GP_OUTPUTS using the helper function
handle_managed_dir "${APP_LORAS_DIR}" "$W2GP_LORAS" "W2GP_LORAS"
handle_managed_dir "${APP_CKPTS_DIR}" "$W2GP_MODELS" "W2GP_MODELS"
handle_managed_dir "${APP_SETTINGS_DIR}" "$W2GP_SETTINGS" "W2GP_SETTINGS"
handle_managed_dir "${APP_OUTPUTS_DIR}" "$W2GP_OUTPUTS" "W2GP_OUTPUTS"

# 2. Create symlinks for specific LoRA types to point to the (potentially re-mapped or mounted) APP_LORAS_DIR
# This runs after APP_LORAS_DIR is settled (either as default, symlinked via W2GP_LORAS, or a direct mount).
echo "Setting up specific LoRA type symlinks to point to ${APP_LORAS_DIR}..." >&2 # Redirect to stderr
LORA_TYPE_TARGET_DIRS=(
    "${APP_LORAS_HUNYUAN_DIR}"
    "${APP_LORAS_HUNYUAN_I2V_DIR}"
    "${APP_LORAS_I2V_DIR}"
    "${APP_LORAS_LTXV_DIR}"
)
for lora_type_target_dir in "${LORA_TYPE_TARGET_DIRS[@]}"; do
    rm -rf "${lora_type_target_dir}"
    ln -s "${APP_LORAS_DIR}" "${lora_type_target_dir}"
    echo "Symlinked ${lora_type_target_dir} -> ${APP_LORAS_DIR}" >&2 # Redirect to stderr
done

echo "Application directory and LoRA symlink setup complete." >&2 # Redirect to stderr
echo "  Checkpoints/Models will use: ${APP_CKPTS_DIR} (resolved: $(readlink -f "${APP_CKPTS_DIR}" 2>/dev/null || echo "${APP_CKPTS_DIR}"))" >&2 # Redirect to stderr
echo "  Outputs will use:            ${APP_OUTPUTS_DIR} (resolved: $(readlink -f "${APP_OUTPUTS_DIR}" 2>/dev/null || echo "${APP_OUTPUTS_DIR}"))" >&2 # Redirect to stderr
echo "  Settings will use:           ${APP_SETTINGS_DIR} (resolved: $(readlink -f "${APP_SETTINGS_DIR}" 2>/dev/null || echo "${APP_SETTINGS_DIR}"))" >&2 # Redirect to stderr
echo "  Central LoRA storage at:     ${APP_LORAS_DIR} (resolved: $(readlink -f "${APP_LORAS_DIR}" 2>/dev/null || echo "${APP_LORAS_DIR}"))" >&2 # Redirect to stderr
echo "  Hunyuan LoRAs path:          ${APP_LORAS_HUNYUAN_DIR} (-> ${APP_LORAS_DIR})" >&2 # Redirect to stderr
echo "  Hunyuan I2V LoRAs path:      ${APP_LORAS_HUNYUAN_I2V_DIR} (-> ${APP_LORAS_DIR})" >&2 # Redirect to stderr
echo "  I2V LoRAs path:              ${APP_LORAS_I2V_DIR} (-> ${APP_LORAS_DIR})" >&2 # Redirect to stderr
echo "  LTXV LoRAs path:             ${APP_LORAS_LTXV_DIR} (-> ${APP_LORAS_DIR})" >&2 # Redirect to stderr
echo "------------------------" >&2 # Redirect to stderr

# --- Construct Wan2GP Command ---
# Base command
COMMAND_ARGS=("python" "wgp.py")

# --- Handle "sticky default listen" ---
# Default to adding --listen, unless W2GP_LISTEN is explicitly "false"
add_listen_flag=true
if [ -n "$W2GP_LISTEN" ] && [[ "$W2GP_LISTEN" == "false" ]]; then
    echo "W2GP_LISTEN is set to 'false'. The --listen flag will be omitted." >&2 # Redirect to stderr
    add_listen_flag=false
else
    if [ -n "$W2GP_LISTEN" ] && [[ "$W2GP_LISTEN" == "true" ]]; then
        echo "W2GP_LISTEN is set to 'true'. The --listen flag will be included." >&2 # Redirect to stderr
    else
        echo "W2GP_LISTEN is not set or not 'false'. Defaulting to include --listen flag." >&2 # Redirect to stderr
    fi
fi

if $add_listen_flag; then
    COMMAND_ARGS+=("--listen")
fi

# --- Handle other W2GP_ core arguments independently ---
# W2GP_PROFILE
if [ -n "$W2GP_PROFILE" ]; then
    COMMAND_ARGS+=("--profile" "$W2GP_PROFILE")
    echo "Using profile: $W2GP_PROFILE" >&2 # Redirect to stderr
else
    echo "W2GP_PROFILE not set. wgp.py will use its default profile." >&2 # Redirect to stderr
fi

# W2GP_SERVER_PORT
if [ -n "$W2GP_SERVER_PORT" ]; then
    COMMAND_ARGS+=("--server-port" "$W2GP_SERVER_PORT")
    echo "Using server port: $W2GP_SERVER_PORT" >&2 # Redirect to stderr
fi

# W2GP_SERVER_NAME
if [ -n "$W2GP_SERVER_NAME" ]; then
    COMMAND_ARGS+=("--server-name" "$W2GP_SERVER_NAME")
    echo "Using server name: $W2GP_SERVER_NAME" >&2 # Redirect to stderr
fi

# Add any other arguments passed via Dockerfile CMD or `docker run ... image cmd_arg1 cmd_arg2`
# These are appended after the W2GP-derived arguments.
if [ "$#" -gt 0 ]; then
    echo "Appending additional arguments from CMD/run: $@" >&2 # Redirect to stderr
    COMMAND_ARGS+=("$@")
fi

echo "--- Wan2GP Execution ---" >&2 # Redirect to stderr
echo "Final command to be executed: ${COMMAND_ARGS[*]}" >&2 # Redirect to stderr
echo "------------------------" >&2 # Redirect to stderr

# Execute the command
exec "${COMMAND_ARGS[@]}"
