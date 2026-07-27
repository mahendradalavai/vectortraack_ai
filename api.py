import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Dict, List, Optional

import anyio
import cv2
from fastapi import FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from ultralytics import YOLO

from firebase_config import save_detection

# Define directories
BASE_DIR = Path(__file__).resolve().parent
UPLOADS_DIR = BASE_DIR / "uploads"
RESULTS_DIR = BASE_DIR / "results"
MODEL_PATH = BASE_DIR / "models" / "best.pt"

# Initialize global model variable
model: Optional[YOLO] = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan event handler to manage startup and shutdown processes."""
    global model
    # Ensure directories exist
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Model weights not found at {MODEL_PATH.resolve()}. "
            "Please ensure 'models/best.pt' is present before starting the server."
        )
    
    print(f"[API] Loading YOLO model from {MODEL_PATH.resolve()}...")
    model = YOLO(str(MODEL_PATH))
    print("[API] YOLO Model loaded successfully and ready for inference.")
    yield
    print("[API] Shutting down application and clearing model.")
    model = None

app = FastAPI(
    title="VectorTrack AI API",
    description="FastAPI backend bridge for YOLOv8 object detection on VectorTrack AI",
    version="1.0.0",
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for mobile/local API access
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount static file directories to serve original and annotated images
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_DIR)), name="uploads")
app.mount("/results", StaticFiles(directory=str(RESULTS_DIR)), name="results")

@app.get("/health", status_code=status.HTTP_200_OK)
async def health_check():
    """Health check endpoint to verify server and model status."""
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "model_name": MODEL_PATH.name if MODEL_PATH.exists() else "Not Found"
    }

@app.post("/detect/image", status_code=status.HTTP_201_CREATED)
async def detect_image(
    file: UploadFile = File(...),
    source: str = Form("camera")
):
    """
    Endpoint to receive an image, run YOLOv8 object detection,
    save metadata to Firestore, and return detection results and image URLs.
    """
    if model is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YOLO model is not loaded."
        )
    
    # Validate file extension
    file_ext = Path(file.filename).suffix.lower()
    allowed_extensions = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
    if file_ext not in allowed_extensions:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported image format. Allowed formats: {', '.join(allowed_extensions)}"
        )
        
    # Read the image content
    try:
        content = await file.read()
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not read upload file: {str(e)}"
        )
        
    # Generate unique filename to avoid collision
    unique_suffix = f"{int(time.time())}_{uuid.uuid4().hex[:6]}"
    filename = f"img_{unique_suffix}{file_ext}"
    
    original_path = UPLOADS_DIR / filename
    result_path = RESULTS_DIR / filename
    
    # Save the original uploaded image file
    try:
        await anyio.Path(original_path).write_bytes(content)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save original image: {str(e)}"
        )
        
    # Run YOLOv8 detection in a threadpool to prevent blocking the event loop
    try:
        results = await run_in_threadpool(model, str(original_path))
    except Exception as e:
        # Cleanup uploaded file on failure
        if original_path.exists():
            original_path.unlink()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"YOLO inference failed: {str(e)}"
        )
        
    detections: List[Dict] = []
    detections_found = False
    
    # Iterate over detection results
    for result in results:
        boxes = result.boxes
        if boxes is None or len(boxes) == 0:
            continue
            
        detections_found = True
        for box in boxes:
            class_id = int(box.cls[0])
            class_name = model.names[class_id]
            confidence = float(box.conf[0])
            
            # Bounding box coordinates (x_min, y_min, x_max, y_max)
            bbox = [float(coord) for coord in box.xyxy[0]]
            
            detections.append({
                "class": class_name,
                "confidence": confidence,
                "bbox": bbox
            })
            
            # Save each detection to Firestore in a threadpool
            await run_in_threadpool(
                save_detection,
                class_name=class_name,
                confidence=confidence,
                image_name=filename,
                image_path=str(original_path),
                source=source
            )
            
    # Save the annotated image with bounding boxes in a threadpool
    if detections_found:
        try:
            annotated_image = results[0].plot()
            await run_in_threadpool(cv2.imwrite, str(result_path), annotated_image)
        except Exception as e:
            print(f"[API] Error saving annotated image: {e}")
            
    return {
        "success": True,
        "message": "Detection completed successfully." if detections_found else "No objects detected.",
        "image_name": filename,
        "source": source,
        "detections": detections,
        "original_image_url": f"/uploads/{filename}",
        "result_image_url": f"/results/{filename}" if result_path.exists() else None
    }
