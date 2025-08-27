FROM nvidia/cuda:12.8.1-devel-ubuntu24.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 python3-pip git wget libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Disable externally managed Python environment
RUN rm /usr/lib/python*/EXTERNALLY-MANAGED

# Install PyTorch with xFormers
RUN pip install --no-cache-dir \
    torch==2.7.0 torchvision torchaudio xformers --index-url https://download.pytorch.org/whl/cu128

# Clone Wan2GP to final location and install dependencies
RUN git clone https://github.com/deepbeepmeep/Wan2GP.git /app/Wan2GP && \
    pip install --no-cache-dir -r /app/Wan2GP/requirements.txt

# Install Sage Attention support
RUN pip install --no-cache-dir \
    sageattention==1.0.6

# Install Sage Attention 2 support for CUDA Compute Capability 9.0 (H100)
RUN git clone https://github.com/thu-ml/SageAttention /tmp/SageAttention && \
    cd /tmp/SageAttention && \
    sed -i 's/compute_capabilities = set()/compute_capabilities = {"9.0"}/' setup.py && \
    pip install . && \
    rm -rf /tmp/SageAttention

# Set working directory
WORKDIR /app/Wan2GP

# Start the app
CMD ["python3", "wgp.py", "--listen", "--profile", "1", "--fp16"]
