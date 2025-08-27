# Base Image: Official PyTorch image with PyTorch 2.7.0, CUDA 12.8.0, dan development tools.
# This image uses Conda for Python environment management.
FROM pytorch/pytorch:2.7.0-cuda12.8-cudnn9-devel

# Set maintainer label
LABEL maintainer="thankfulcarp@example.com"

# Set environment variables
# - DEBIAN_FRONTEND=noninteractive: Prevents interactive prompts during package installation.
# - PYTHONUNBUFFERED=1: Ensures Python output is sent straight to terminal (good for Docker logs).
# - TORCH_CUDA_ARCH_LIST: For compiling CUDA extensions like FlashAttention.
#   Targeting Ampere (8.6 for 3050/3090) and Ada Lovelace (8.9 for 4090/A6000 Ada).
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    TORCH_CUDA_ARCH_LIST="8.6 8.9"
    # Optional Wan2GP environment variables can be set here or via start.sh/runtime:
    # WGP_PROFILE="3"
    # WGP_LORA_DIR="/workspace/loras" # Assuming models/loras are mounted to /workspace

# System dependencies
# Update package lists and install common utilities.
# The base image should already have git and build-essential as it's a -devel image,
# but explicitly listing them ensures they are present.
# Python is managed by Conda in the base image.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    aria2 \
    ffmpeg \
    build-essential \
    openssh-server \
    rsync \
    net-tools \
    # Add any other essential system-level packages Wan2GP might need that aren't Python packages
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip, setuptools, and wheel within the Conda environment's Python
# The base image provides Python via Conda. Its pip should be on the PATH.
RUN pip install --upgrade pip setuptools wheel

# Set up the working directory for Wan2GP
WORKDIR /app

# 0. Download Wan2GP source code (Wan2GP step 0)
ARG WAN2GP_REPO=https://github.com/deepbeepmeep/Wan2GP.git
ARG WAN2GP_BRANCH=main
RUN git clone --depth 1 --branch ${WAN2GP_BRANCH} ${WAN2GP_REPO} .
# 2. Install pip dependencies from requirements.txt (Wan2GP step 2)
# This uses the pip from the Conda environment in the base image.
RUN if [ -f requirements.txt ]; then \
        pip install -r requirements.txt; \
    else \
        echo "requirements.txt not found in /app, skipping pip install -r requirements.txt"; \
    fi

# --- Optional Attention Mechanisms (Wan2GP step 3) ---
# These require the CUDA toolkit (nvcc, etc.) from the base image for compilation.
# 3.1 Optional Sage Attention support
RUN pip install sageattention==1.0.6

# 3.2 Optional Sage 2 Attention support (Linux Manual Compilation)
RUN git clone https://github.com/thu-ml/SageAttention /tmp/SageAttention
WORKDIR /tmp/SageAttention
RUN \
    # Patch setup.py: After 'compute_capabilities = set()', insert logic to populate it from TORCH_CUDA_ARCH_LIST
    # Ensure the printed Python code has correct indentation (0 for the start of the block if inserted at global scope).
    awk '1; /^[[:space:]]*compute_capabilities = set\(\)/ { \
        print "# --- BEGIN SAGE_SETUP_PATCH for Docker build ---"; \
        print "_arch_list_env_var = os.environ.get(\"TORCH_CUDA_ARCH_LIST\")"; \
        print "if not compute_capabilities and _arch_list_env_var:"; \
        print "    print(f\"[SAGE_SETUP_PATCH] No GPUs detected by torch.cuda.device_count(), using TORCH_CUDA_ARCH_LIST: {_arch_list_env_var!r}\")"; \
        print "    for _arch_spec in _arch_list_env_var.replace(\";\", \" \").split():"; \
        print "        _arch = _arch_spec.split(\"+\")[0]"; \
        print "        if _arch in SUPPORTED_ARCHS:"; \
        print "            compute_capabilities.add(_arch)"; \
        print "            print(f\"[SAGE_SETUP_PATCH] Added capability: {_arch!r}\")"; \
        print "        else:"; \
        print "            print(f\"[SAGE_SETUP_PATCH] Warning: Arch {_arch!r} from TORCH_CUDA_ARCH_LIST ({_arch_list_env_var!r}) not in SageAttention SUPPORTED_ARCHS ({SUPPORTED_ARCHS!r}).\")"; \
        print "    if compute_capabilities:"; \
        print "        print(f\"[SAGE_SETUP_PATCH] Populated compute_capabilities from TORCH_CUDA_ARCH_LIST: {compute_capabilities!r}\")"; \
        print "    else:"; \
        print "        print(\"        # This print is for a Python comment, indentation here refers to Python comment indent\")"; \
        print "        print(f\"[SAGE_SETUP_PATCH] ERROR: TORCH_CUDA_ARCH_LIST ({_arch_list_env_var!r}) did not yield any architectures in SUPPORTED_ARCHS ({SUPPORTED_ARCHS!r}).\")"; \
        print "# --- END SAGE_SETUP_PATCH ---"; \
    }' setup.py > setup.py.patched && mv setup.py.patched setup.py && \
    # For SageAttention, specifically use TORCH_CUDA_ARCH_LIST="8.9" to target Ada Lovelace.
    # This is a workaround for its setup.py not handling multiple gencodes well for its specific kernels.
    # This ensures the SM89 kernels are built, and SM80 kernels are built targeting SM89.
    TORCH_CUDA_ARCH_LIST="8.9" pip install --no-build-isolation .
WORKDIR /app
RUN rm -rf /tmp/SageAttention

# 3.3 Optional Flash Attention support
# Uses the globally set TORCH_CUDA_ARCH_LIST="8.6 8.9"
RUN pip install flash-attn==2.7.2.post1 --no-build-isolation

# --- Model Handling ---
# Wan2GP's wgp.py script is expected to handle the download of its own base models.
# For LoRAs and other large files, mount them as volumes at runtime.
# Example: -v /path/to/host/loras:/workspace/loras_t2v (if start.sh points there)

# --- Expose Ports ---
# Wan2GP (wgp.py) typically runs a Gradio web UI.
EXPOSE 7860
EXPOSE 22

# --- User and Permissions (Optional, but good practice) ---
# The base PyTorch image might run as root or a predefined user.
# If you need a specific user:
# RUN useradd -ms /bin/bash appuser && \
#     chown -R appuser:appuser /app
# USER appuser
# WORKDIR /app # Or /home/appuser/app

# --- Entrypoint & CMD ---
# Override the base image's entrypoint to use our custom start.sh
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENTRYPOINT ["/app/start.sh"]
CMD []
