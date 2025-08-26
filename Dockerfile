# Gunakan base image yang sudah ditentukan
FROM pytorch/pytorch:2.4.0-cuda12.4-cudnn9-devel

# Atur working directory
WORKDIR /app

COPY . .

# Install dependencies
RUN pip install -r requirements.txt && rm -rf /root/.cache/pip



# Expose port Gradio
EXPOSE 7860

# Entrypoint akan mengunduh model dan menjalankan aplikasi Gradio
CMD [ "python", "wgp.py" ]
