# Use the official lightweight Python image
FROM python:3.10-slim

# Set system-level environment variables
# Supabase credentials are supplied at runtime (docker run -e ... or your
# platform's secret manager); they are never baked into the image.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080 \
    NUMBA_CACHE_DIR=/tmp \
    VECTORTRACK_TMP_DIR=/tmp/vectortrack

# Set the working directory in the container
WORKDIR /app

# Install system dependencies required for OpenCV, PyTorch, and YOLOv8
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip and install wheel
RUN pip install --no-cache-dir --upgrade pip wheel setuptools

# Copy requirements file first to leverage Docker layer caching
COPY requirements.txt .

# Install CPU-specific PyTorch wheels to keep the container size small and lightweight
# (Cloud Run instances do not have GPUs on standard tiers, so CPU PyTorch is much faster to pull/deploy)
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Install remaining dependencies from requirements
RUN pip install --no-cache-dir -r requirements.txt

# Copy all project files into the container working directory
COPY . .

# Scratch directory for the media files YOLO/OpenCV need on disk. They are
# deleted after each request; Supabase Storage holds the permanent copies.
RUN mkdir -p /tmp/vectortrack && chmod -R 777 /tmp/vectortrack

# Expose port
EXPOSE 8080

# Start the application using Uvicorn
CMD uvicorn api:app --host 0.0.0.0 --port ${PORT}
