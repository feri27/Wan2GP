# Base image with CUDA 12.4, suitable for PyTorch 2.6.0 builds
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Runtime environment configuration
ENV DEBIAN_FRONTEND=noninteractive \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:$PATH \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH \
    PYTHONUNBUFFERED=1 \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# Install required system libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    libgl1-mesa-glx \
    libglib2.0-0 \
    python3.10 \
    python3-pip \
    python3.10-venv \
    python3.10-dev \
    build-essential \
    gcc \
    && python3 -m pip install --upgrade pip \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Retrieve Wan2GP repo and archive it for use at runtime
RUN git clone --depth=1 https://github.com/deepbeepmeep/Wan2GP.git Wan2GP && \
    tar -czf Wan2GP.tar.gz Wan2GP && \
    rm -rf Wan2GP

# Copy container startup script
COPY startup-gpu-poor.sh startup-gpu-poor.sh
RUN chmod +x startup-gpu-poor.sh

# Default exposed port for Gradio UI
EXPOSE 7860

# Runtime config defaults
ENV AUTO_UPDATE=0

# Container launch command
CMD ["bash", "./start.sh"]

## To Build and Run:
## Note: Adjust the volume path as needed for your environment
## To run with GPU support, ensure you have the NVIDIA Container Toolkit installed

# docker build -t ai-wan-gp -f dockerfile-gpu-poor .
# docker run -it --rm --name ai-wan-gp --gpus all --shm-size=24g -p 7860:7860 -v "C:/_Models/wan:/workspace" -v "C:/_Models/wan/cache:/app/cache" -e AUTO_UPDATE=0 ai-wan-gp
