"""VectorTrack AI FastAPI backend.

Serves the UAV garbage/rubbish detection dashboard, runs YOLOv8 + OpenCV
inference for image and video uploads, and persists results to Supabase:

* originals and annotated outputs go to Supabase Storage,
* one row per detected object is inserted into ``public.detections``,
* private objects are handed to the dashboard as time-limited signed URLs.

Every database and storage write uses the service-role key, which only ever
lives in this server process. Media files are staged in a temporary directory
for the duration of a request and are always removed afterwards.
"""

import base64
import os
import tempfile
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Dict, List, Optional

import anyio
import cv2
from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from ultralytics import YOLO

# `require_user` is still exported for endpoints that must have a session;
# the detection endpoints deliberately use the optional variant.
from auth import AuthUser, optional_user, require_user  # noqa: F401
from config import settings
from supabase_client import (
    create_signed_url,
    insert_detection,
    resolve_app_user_id,
    upload_media,
)

# Define directories
BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "models" / "best.pt"
FALLBACK_MODEL_PATH = BASE_DIR / "yolov8n.pt"

# Scratch space for the files OpenCV/YOLO need on disk. Anything written here
# is deleted before the request finishes: Supabase Storage is the permanent
# store, the local filesystem is not.
SCRATCH_DIR = Path(os.getenv("VECTORTRACK_TMP_DIR") or (Path(tempfile.gettempdir()) / "vectortrack"))
SCRATCH_DIR.mkdir(parents=True, exist_ok=True)

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
VIDEO_EXTENSIONS = {".mp4", ".avi", ".mov", ".mkv", ".webm"}

IMAGE_CONTENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".bmp": "image/bmp",
}
VIDEO_CONTENT_TYPES = {
    ".mp4": "video/mp4",
    ".avi": "video/x-msvideo",
    ".mov": "video/quicktime",
    ".mkv": "video/x-matroska",
    ".webm": "video/webm",
}

# Initialize global model variable
model: Optional[YOLO] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan event handler to manage startup and shutdown processes."""
    global model
    model_path = MODEL_PATH if MODEL_PATH.exists() else FALLBACK_MODEL_PATH
    if not model_path.exists():
        raise FileNotFoundError(
            f"Model weights not found at {MODEL_PATH.resolve()} or "
            f"{FALLBACK_MODEL_PATH.resolve()}."
        )

    print(f"[API] Loading YOLO model from {model_path.resolve()}...")
    model = YOLO(str(model_path))
    print("[API] YOLO Model loaded successfully and ready for inference.")
    if not settings.is_configured:
        print(
            "[API] Supabase is not configured yet (missing: "
            + ", ".join(settings.missing_required())
            + "). Inference works, but detections cannot be stored."
        )
    yield
    print("[API] Shutting down application and clearing model.")
    model = None


app = FastAPI(
    title="VectorTrack AI API",
    description="FastAPI backend bridge for YOLOv8 object detection on VectorTrack AI",
    version="1.0.0",
    lifespan=lifespan,
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount the static dashboard assets
app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")


def _model_name() -> str:
    if MODEL_PATH.exists():
        return MODEL_PATH.name
    if FALLBACK_MODEL_PATH.exists():
        return FALLBACK_MODEL_PATH.name
    return "Not Found"


def _storage_path(user_id: Optional[str], media_type: str, filename: str) -> str:
    """Object key inside a bucket: ``{user_id}/{media_type}/{filename}``.

    The leading user id is what the Storage RLS policies match on, so a
    browser session can only ever read objects it owns. Signed-out scans use
    the ``anonymous`` folder for the very same reason.
    """
    owner = user_id or "anonymous"
    return f"{owner}/{media_type}/{filename}"


def _acting_user_id(user: Optional[AuthUser]) -> Optional[str]:
    """The identity a detection is attributed to.

    A signed-in user always wins. Without a session the shared app account is
    used so the dashboard works before sign-in; when Supabase is not available
    at all this returns ``None`` and only media is stored.
    """
    if user is not None and user.id:
        return user.id
    return resolve_app_user_id()


async def _store_media_and_detections(
    *,
    user_id: Optional[str],
    media_type: str,
    filename: str,
    original_bytes: bytes,
    result_bytes: Optional[bytes],
    content_type: str,
    result_content_type: str,
    source: str,
    detections: List[Dict[str, Any]],
    metadata_extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Upload media to Supabase Storage and record one row per detection.

    Returns the signed URLs plus the ids of the inserted rows. Failures are
    reported through the ``warning`` field instead of raising, so a cloud
    hiccup never hides the inference result from the operator.
    """
    original_path = _storage_path(user_id, media_type, filename)
    result_path = _storage_path(user_id, media_type, filename)

    warning: Optional[str] = None

    uploaded_original = await run_in_threadpool(
        upload_media, settings.originals_bucket, original_path, original_bytes, content_type
    )
    if uploaded_original is None:
        warning = (
            "Supabase Storage upload failed for the original file; "
            "media is not available for this scan."
        )

    uploaded_result: Optional[str] = None
    if result_bytes is not None:
        uploaded_result = await run_in_threadpool(
            upload_media,
            settings.results_bucket,
            result_path,
            result_bytes,
            result_content_type,
        )
        if uploaded_result is None and warning is None:
            warning = (
                "Supabase Storage upload failed for the annotated output; "
                "only the original media was stored."
            )

    original_url = None
    if uploaded_original:
        original_url = await run_in_threadpool(
            create_signed_url, settings.originals_bucket, original_path
        )

    result_url = None
    if uploaded_result:
        result_url = await run_in_threadpool(
            create_signed_url, settings.results_bucket, result_path
        )

    detection_ids: List[Optional[str]] = []
    if user_id:
        for detection in detections:
            metadata: Dict[str, Any] = {
                "bbox": detection.get("bbox"),
                "media_file": filename,
                "model": _model_name(),
            }
            if detection.get("frame") is not None:
                metadata["frame"] = detection["frame"]
            if metadata_extra:
                metadata.update(metadata_extra)

            row = await run_in_threadpool(
                insert_detection,
                user_id=user_id,
                class_name=detection["class"],
                confidence=detection["confidence"],
                source=source,
                media_type=media_type,
                original_file_path=uploaded_original,
                result_file_path=uploaded_result,
                metadata=metadata,
            )
            detection_ids.append((row or {}).get("id") if isinstance(row, dict) else None)
    elif warning is None:
        warning = (
            "No storage identity is available, so the detections were not recorded; "
            "the media and results for this scan are shown inline only."
        )

    return {
        "original_url": original_url,
        "result_url": result_url,
        "media_stored": bool(uploaded_original or uploaded_result),
        "detection_ids": [row_id for row_id in detection_ids if row_id],
        "warning": warning,
    }


@app.get("/", response_class=HTMLResponse)
async def serve_dashboard():
    """Serve the UAV Object Detection Dashboard HTML page."""
    index_path = BASE_DIR / "static" / "index.html"
    if not index_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Dashboard index.html not found.",
        )
    return index_path.read_text(encoding="utf-8")


@app.get("/health", status_code=status.HTTP_200_OK)
async def health_check():
    """Health check endpoint to verify server and model status."""
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "model_name": _model_name(),
        "supabase_configured": settings.is_configured,
    }


@app.get("/config", status_code=status.HTTP_200_OK)
async def public_config():
    """Public runtime configuration for the dashboard.

    Only values that are safe to expose in a browser are returned. The
    service-role key is never included here.
    """
    return {
        "supabase_url": settings.supabase_url or None,
        "supabase_anon_key": settings.supabase_anon_key or None,
        "originals_bucket": settings.originals_bucket,
        "results_bucket": settings.results_bucket,
        "configured": settings.is_configured,
    }


@app.post("/detect/image", status_code=status.HTTP_201_CREATED)
async def detect_image(
    file: UploadFile = File(...),
    source: str = Form("camera"),
    conf: float = Form(0.10),
    iou: float = Form(0.45),
    user: Optional[AuthUser] = Depends(optional_user),
):
    """
    Endpoint to receive an image, run YOLOv8 object detection,
    store the media in Supabase Storage, record the detections in Postgres,
    and return detection results plus signed media URLs.

    Works with or without a session: a signed-in user owns the stored rows and
    media, while a signed-out scan is attributed to the shared app account.
    """
    if model is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YOLO model is not loaded.",
        )

    # Validate file extension
    file_ext = Path(file.filename or "").suffix.lower()
    if file_ext not in IMAGE_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported image format. Allowed formats: {', '.join(sorted(IMAGE_EXTENSIONS))}",
        )

    # Read the image content
    try:
        content = await file.read()
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not read upload file: {str(e)}",
        )

    if not content:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded image is empty.",
        )

    user_id = await run_in_threadpool(_acting_user_id, user)
    identity_mode = "signed-in" if (user is not None and user.id) else "app-account"

    # Generate unique filename to avoid collision
    unique_suffix = f"{int(time.time())}_{uuid.uuid4().hex[:6]}"
    filename = f"img_{unique_suffix}{file_ext}"
    content_type = IMAGE_CONTENT_TYPES.get(file_ext, "application/octet-stream")

    # Temporary working directory — always removed when the request ends.
    with tempfile.TemporaryDirectory(dir=str(SCRATCH_DIR), prefix="img-") as workdir:
        original_path = Path(workdir) / filename
        result_path = Path(workdir) / filename

        # Save the original uploaded image so YOLO can read it from disk
        try:
            await anyio.Path(original_path).write_bytes(content)
        except OSError as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to stage the uploaded image for inference: {str(e)}",
            )

        # Run YOLOv8 detection in a threadpool to prevent blocking the event loop
        try:
            results = await run_in_threadpool(
                lambda: model(str(original_path), conf=conf, iou=iou)
            )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"YOLO inference failed: {str(e)}",
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
                    "bbox": bbox,
                })

        # Always render the annotated image (even with no detections) so the
        # operator can see what the model produced.
        result_bytes: Optional[bytes] = None
        annotated_image: Optional[Any] = None
        if results:
            try:
                annotated_image = results[0].plot()
                written = await run_in_threadpool(cv2.imwrite, str(result_path), annotated_image)
                if written:
                    result_bytes = result_path.read_bytes()
            except Exception as e:
                print(f"[API] Error saving annotated image: {e}")

        # Inline fallback so the annotated result is visible even when Storage
        # is unavailable (not configured, or the buckets have not been created).
        result_data_url: Optional[str] = None
        if result_bytes:
            result_data_url = "data:image/jpeg;base64," + base64.b64encode(result_bytes).decode("ascii")
        elif annotated_image is not None:
            try:
                ok, buffer = await run_in_threadpool(cv2.imencode, ".jpg", annotated_image)
                if ok:
                    result_data_url = "data:image/jpeg;base64," + base64.b64encode(
                        buffer.tobytes()
                    ).decode("ascii")
            except Exception as e:
                print(f"[API] Could not build the inline annotated image: {e}")

        stored = await _store_media_and_detections(
            user_id=user_id,
            media_type="image",
            filename=filename,
            original_bytes=content,
            result_bytes=result_bytes,
            content_type=content_type,
            result_content_type="image/jpeg",
            source=source,
            detections=detections,
            metadata_extra={"conf_threshold": conf, "iou_threshold": iou},
        )

    if stored["warning"]:
        print(f"[API] Warning: {stored['warning']}")

    return {
        "success": True,
        "message": "Detection completed successfully." if detections_found else "No objects detected.",
        "image_name": filename,
        "source": source,
        "conf_threshold": conf,
        "detections": detections,
        "original_image_url": stored["original_url"],
        "result_image_url": stored["result_url"],
        # Only populated when Storage could not serve the annotated image.
        "result_image_data_url": result_data_url if stored["result_url"] is None else None,
        "identity_mode": identity_mode,
        "detection_count": len(detections),
        "detection_ids": stored["detection_ids"],
        "media_stored": stored["media_stored"],
        "warning": stored["warning"],
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
    user: Optional[AuthUser] = Depends(optional_user),
):
    """
    Accept a video upload, run YOLOv8 detection on every frame, store the
    original and annotated videos in Supabase Storage, record the detections
    in Postgres, and return a detection summary with signed media URLs.

    Like image detection, this works with or without a Supabase session.
    """
    if model is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YOLO model is not loaded.",
        )

    file_ext = Path(file.filename or "").suffix.lower()
    if file_ext not in VIDEO_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported video format. Allowed: {', '.join(sorted(VIDEO_EXTENSIONS))}",
        )

    # Read content
    try:
        content = await file.read()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not read video file: {e}")

    if not content:
        raise HTTPException(status_code=400, detail="Uploaded video is empty.")

    unique_suffix  = f"{int(time.time())}_{uuid.uuid4().hex[:6]}"
    filename       = f"vid_{unique_suffix}{file_ext}"
    content_type   = VIDEO_CONTENT_TYPES.get(file_ext, "application/octet-stream")

    user_id = await run_in_threadpool(_acting_user_id, user)
    identity_mode = "signed-in" if (user is not None and user.id) else "app-account"

    with tempfile.TemporaryDirectory(dir=str(SCRATCH_DIR), prefix="vid-") as workdir:
        original_path = Path(workdir) / filename
        result_path   = Path(workdir) / filename

        # Save original
        try:
            await anyio.Path(original_path).write_bytes(content)
        except OSError as e:
            raise HTTPException(
                status_code=500,
                detail=f"Failed to stage the uploaded video for inference: {e}",
            )

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
            raise HTTPException(status_code=500, detail=f"Video inference failed: {e}")

        result_bytes: Optional[bytes] = None
        try:
            if result_path.exists() and result_path.stat().st_size > 0:
                result_bytes = result_path.read_bytes()
        except OSError as e:
            print(f"[API] Error reading annotated video: {e}")

        stored = await _store_media_and_detections(
            user_id=user_id,
            media_type="video",
            filename=filename,
            original_bytes=content,
            result_bytes=result_bytes,
            content_type=content_type,
            result_content_type=VIDEO_CONTENT_TYPES.get(file_ext, "video/mp4"),
            source=source,
            detections=summary["detections"][:50],   # record the first 50 hits
            metadata_extra={
                "conf_threshold": conf,
                "iou_threshold": iou,
                "frames_processed": summary["frames_processed"],
                "total_frames": summary["total_frames"],
                "total_detections": summary["total_detections"],
                "class_counts": summary["class_counts"],
            },
        )

    if stored["warning"]:
        print(f"[API] Warning: {stored['warning']}")

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
        "original_video_url": stored["original_url"],
        "result_video_url":   stored["result_url"],
        "identity_mode":      identity_mode,
        "detection_count":    len(stored["detection_ids"]),
        "detection_ids":      stored["detection_ids"],
        "media_stored":       stored["media_stored"],
        "warning":            stored["warning"],
    }
