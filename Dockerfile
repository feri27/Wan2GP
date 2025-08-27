# Base Image: Official PyTorch image with PyTorch 2.6.0, CUDA 12.4.1, cuDNN 9, and development tools.
# This image uses Conda for Python environment management.
FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-devel

# Set maintainer label
LABEL maintainer="anjar@example.com"

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

# Install Sage Attention support
RUN pip install --no-cache-dir \
    sageattention==1.0.6

# Install Sage Attention 2 support for CUDA Compute Capability 9.0 (H100)
RUN git clone https://github.com/thu-ml/SageAttention /tmp/SageAttention && \
    cd /tmp/SageAttention && \
    sed -i 's/compute_capabilities = set()/compute_capabilities = {"9.0"}/' setup.py && \
    pip install . && \
    rm -rf /tmp/SageAttention

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
