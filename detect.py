"""Run YOLO video inference for VectorTrack AI.

Loads the trained model from ``models/best.pt``, runs detection on a video
in ``videos/``, prints a summary, and saves the annotated output to ``output/``.
"""

from collections import Counter
from pathlib import Path

from ultralytics import YOLO

from firebase_config import save_detection


MODEL_PATH = Path("models/best.pt")
VIDEOS_DIR = Path("videos")
OUTPUT_DIR = Path("output")
VIDEO_EXTENSIONS = {".mp4", ".avi", ".mov", ".mkv", ".webm"}


def get_video_path() -> Path:
    """Use the first supported video file in the videos folder."""
    if not VIDEOS_DIR.exists():
        raise FileNotFoundError(
            f"Videos folder not found: {VIDEOS_DIR.resolve()}. "
            "Please add a test video before running inference."
        )

    videos = sorted(
        path for path in VIDEOS_DIR.iterdir()
        if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS
    )

    if not videos:
        raise FileNotFoundError(
            f"No videos found in {VIDEOS_DIR.resolve()}. "
            f"Supported formats: {', '.join(sorted(VIDEO_EXTENSIONS))}"
        )

    return videos[0]


def main() -> None:
    """Run inference on the test video and save annotated output."""
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Model file not found: {MODEL_PATH.resolve()}. "
            "Copy your trained weights to models/best.pt first."
        )

    video_path = get_video_path()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("\n[VectorTrack AI] Loading trained model...")
    model = YOLO(str(MODEL_PATH))

    print(f"[VectorTrack AI] Processing video: {video_path.name}")
    print("[VectorTrack AI] This may take a few minutes depending on video length...\n")

    # Run inference frame by frame and save the annotated video.
    results = model.predict(
        source=str(video_path),
        stream=True,
        save=True,
        project=str(OUTPUT_DIR),
        name="video_detection",
        exist_ok=True,
        verbose=False,
    )

    detection_counts: Counter[str] = Counter()
    frames_with_detections = 0

    for frame_idx, result in enumerate(results, start=1):
        boxes = result.boxes
        if boxes is None or len(boxes) == 0:
            continue

        frames_with_detections += 1
        for box in boxes:
            class_name = model.names[int(box.cls[0])]
            confidence = float(box.conf[0])
            detection_counts[class_name] += 1
            print(f"  Frame {frame_idx}: {class_name} {confidence:.2f}")
            save_detection(
                class_name=class_name,
                confidence=confidence,
                image_name=f"frame_{frame_idx}.jpg",
                image_path=str(video_path),
                source="video"
            )

    output_video = OUTPUT_DIR / "video_detection" / video_path.name

    print("\n[VectorTrack AI] Video processing complete.")
    print(f"[VectorTrack AI] Total frames processed: {len(results)}")
    print(f"[VectorTrack AI] Frames with detections: {frames_with_detections}")

    if detection_counts:
        print("[VectorTrack AI] Detection summary:")
        for class_name, count in detection_counts.most_common():
            print(f"  {class_name}: {count}")
    else:
        print("[VectorTrack AI] No objects detected in the video.")

    print(f"[VectorTrack AI] Saved annotated video to: {output_video}")


if __name__ == "__main__":
    main()
