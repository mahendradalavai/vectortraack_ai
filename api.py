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
from fastapi.responses import HTMLResponse, JSONResponse
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
app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")

@app.get("/", response_class=HTMLResponse)
async def serve_dashboard():
    """Serve the UAV Object Detection Dashboard HTML page."""
    index_path = BASE_DIR / "static" / "index.html"
    if not index_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Dashboard index.html not found."
        )
    return index_path.read_text(encoding="utf-8")

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
    source: str = Form("camera"),
    conf: float = Form(0.10),
    iou: float = Form(0.45)
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
        results = await run_in_threadpool(
            lambda: model(str(original_path), conf=conf, iou=iou)
        )
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
        # Log raw model class names for diagnostics
        print(f"[API] Model classes available: {model.names}")
        if boxes is None or len(boxes) == 0:
            print(f"[API] No boxes detected at conf>={conf} — image may be out of training domain.")
            continue

        detections_found = True
        for box in boxes:
            class_id = int(box.cls[0])
            class_name = model.names[class_id]
            confidence = float(box.conf[0])

            # Bounding box coordinates (x_min, y_min, x_max, y_max)
            bbox = [float(coord) for coord in box.xyxy[0]]

            print(f"[API] Detected: class={class_name}, conf={confidence:.3f}, bbox={bbox}")

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

    # Always save the annotated image (even with no detections) so the
    # user can see what the model output looks like for debugging.
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
        "conf_threshold": conf,
        "detections": detections,
        "original_image_url": f"/uploads/{filename}",
        "result_image_url": f"/results/{filename}" if result_path.exists() else None
    }


# ─────────────────────────────────────────
#  VIDEO DETECTION ENDPOINT
# ─────────────────────────────────────────

def _process_video(video_path: str, result_path: str, conf: float, iou: float) -> dict:
    """
    Synchronous helper — runs YOLO on every frame of a video and writes
    an annotated output video.  Executed inside run_in_threadpool so it
    does not block the FastAPI event loop.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video file: {video_path}")

    fps    = cap.get(cv2.CAP_PROP_FPS) or 25.0
    width  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()

    # cv2.VideoWriter with mp4v codec
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(result_path, fourcc, fps, (width, height))

    detections_summary: List[Dict] = []
    class_counts: Dict[str, int] = {}
    frames_processed = 0

    # Stream results frame-by-frame — memory efficient for large videos
    for result in model(video_path, stream=True, conf=conf, iou=iou, verbose=False):
        frame = result.plot()          # annotated BGR frame
        writer.write(frame)
        frames_processed += 1

        if result.boxes is not None:
            for box in result.boxes:
                cls_name   = model.names[int(box.cls[0])]
                confidence = float(box.conf[0])
                bbox       = [float(c) for c in box.xyxy[0]]
                detections_summary.append({
                    "frame":      frames_processed,
                    "class":      cls_name,
                    "confidence": confidence,
                    "bbox":       bbox,
                })
                class_counts[cls_name] = class_counts.get(cls_name, 0) + 1

    writer.release()

    return {
        "frames_processed": frames_processed,
        "total_frames":     total_frames,
        "total_detections": len(detections_summary),
        "class_counts":     class_counts,
        "detections":       detections_summary[:200],   # cap payload size
    }


@app.post("/detect/video", status_code=status.HTTP_201_CREATED)
async def detect_video(
    file: UploadFile = File(...),
    source: str      = Form("camera"),
    conf: float      = Form(0.10),
    iou:  float      = Form(0.45),
):
    """
    Accept a video upload, run YOLOv8 detection on every frame,
    save an annotated output video, and return a detection summary.
    """
    if model is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YOLO model is not loaded."
        )

    file_ext = Path(file.filename).suffix.lower()
    allowed_video_ext = {".mp4", ".avi", ".mov", ".mkv", ".webm"}
    if file_ext not in allowed_video_ext:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported video format. Allowed: {', '.join(allowed_video_ext)}"
        )

    # Read content
    try:
        content = await file.read()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not read video file: {e}")

    unique_suffix  = f"{int(time.time())}_{uuid.uuid4().hex[:6]}"
    filename       = f"vid_{unique_suffix}{file_ext}"
    original_path  = UPLOADS_DIR / filename
    result_path    = RESULTS_DIR / filename

    # Save original
    try:
        await anyio.Path(original_path).write_bytes(content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save video: {e}")

    # Process in threadpool
    try:
        summary = await run_in_threadpool(
            _process_video,
            str(original_path),
            str(result_path),
            conf,
            iou,
        )
    except Exception as e:
        if original_path.exists():
            original_path.unlink()
        raise HTTPException(status_code=500, detail=f"Video inference failed: {e}")

    # Persist top detections to Firestore
    for det in summary["detections"][:50]:
        try:
            await run_in_threadpool(
                save_detection,
                class_name=det["class"],
                confidence=det["confidence"],
                image_name=filename,
                image_path=str(original_path),
                source=source,
            )
        except Exception:
            pass   # don't fail the whole request if Firestore is slow

    message = (
        f"Video scan complete. {summary['total_detections']} detections across "
        f"{summary['frames_processed']} frames."
        if summary["total_detections"] > 0
        else "Video scan complete. No objects detected."
    )

    return {
        "success":            True,
        "message":            message,
        "video_name":         filename,
        "source":             source,
        "conf_threshold":     conf,
        "frames_processed":   summary["frames_processed"],
        "total_frames":       summary["total_frames"],
        "total_detections":   summary["total_detections"],
        "class_counts":       summary["class_counts"],
        "detections":         summary["detections"],
        "original_video_url": f"/uploads/{filename}",
        "result_video_url":   f"/results/{filename}" if result_path.exists() else None,
    }
