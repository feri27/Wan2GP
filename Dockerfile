# Gunakan base image yang sudah ditentukan
FROM pytorch/pytorch:2.4.0-cuda12.4-cudnn9-devel

# Atur working directory
WORKDIR /app

# Salin semua file dan folder yang diperlukan
COPY . .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose port Gradio
EXPOSE 7860

# Entrypoint akan mengunduh model dan menjalankan aplikasi Gradio
CMD [ "python", "wgp.py" ]
