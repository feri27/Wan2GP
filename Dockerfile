# Gunakan base image yang sudah ditentukan
FROM pytorch/pytorch:2.4.0-cuda12.4-cudnn9-devel

# Atur working directory
WORKDIR /app

# Perbarui paket dan instal dependensi sistem
RUN apt-get update && apt-get install -y ffmpeg

# Salin file requirements.txt
COPY requirements.txt .

# Instal dependensi inti yang paling mungkin berhasil
RUN pip install --no-cache-dir \
    tqdm \
    imageio \
    imageio-ffmpeg \
    einops \
    sentencepiece \
    open_clip_torch>=2.29.0 \
    ftfy \
    piexif \
    pynvml \
    misaki \
    omegaconf \
    hydra-core \
    easydict \
    pydantic==2.10.6 \
    torchdiffeq>=0.2.5 \
    tensordict>=0.6.1 \
    mmgp==3.5.10 \
    matplotlib

# Instal paket yang berpotensi konflik secara terpisah
# Pastikan versi ini kompatibel satu sama lain
RUN pip install --no-cache-dir \
    transformers==4.46.3 \
    diffusers==0.34.0 \
    tokenizers>=0.20.3 \
    accelerate>=1.1.1 \
    peft==0.15.0

# Instal paket video
RUN pip install --no-cache-dir \
    moviepy==1.0.3 \
    av \
    ffmpeg-python \
    pygame>=2.1.0 \
    sounddevice>=0.4.0 \
    soundfile \
    mutagen \
    pyloudnorm \
    librosa==0.11.0

# Instal paket Gradio dan AI tambahan
RUN pip install --no-cache-dir \
    gradio==5.23.0 \
    dashscope \
    loguru

# Instal paket Vision & Segmentation
# (Tindakan ini untuk mengisolasi error jika terjadi)
RUN pip install --no-cache-dir \
    opencv-python>=4.9.0.80 \
    segment-anything \
    timm \
    decord

# Instal paket GPU yang berpotensi menyebabkan masalah
# Jika gagal, coba instal tanpa [gpu]
RUN pip install --no-cache-dir \
    rembg[gpu]==2.0.65 \
    onnxruntime-gpu

# Expose port Gradio
EXPOSE 7860

# Entrypoint akan mengunduh model dan menjalankan aplikasi Gradio
CMD [ "python", "wgp.py" ]
