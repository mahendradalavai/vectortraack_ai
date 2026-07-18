"""Production-ready training entrypoint for VectorTrack AI.

This script uses the latest Ultralytics YOLOv8 API to train a pretrained
``yolov8n.pt`` model on the dataset in ``dataset/data.yaml``.
"""

from pathlib import Path

from ultralytics import YOLO


DATASET_PATH = Path("dataset/data.yaml")
MODEL_NAME = "yolov8n.pt"
EPOCHS = 50
IMGSZ = 640
BATCH = 8
WORKERS = 2
PROJECT = "runs"
NAME = "garbage_detection"


def main() -> None:
    """Run the YOLOv8 training workflow."""
    print("\n[VectorTrack AI] Starting YOLOv8 training...")

    # Validate that the dataset configuration file exists before attempting
    # training. This provides a clear, user-friendly error when the dataset
    # path is missing or misconfigured.
    if not DATASET_PATH.exists():
        raise FileNotFoundError(
            f"Dataset configuration file not found: {DATASET_PATH.resolve()}. "
            "Please ensure the file exists before training."
        )

    print(f"[VectorTrack AI] Loading pretrained model: {MODEL_NAME}")
    model = YOLO(MODEL_NAME)

    print(
        "[VectorTrack AI] Training configuration: "
        f"epochs={EPOCHS}, imgsz={IMGSZ}, batch={BATCH}, workers={WORKERS}, "
        f"project={PROJECT}, name={NAME}"
    )

    print(f"[VectorTrack AI] Using dataset: {DATASET_PATH}")

    # Train the model using the latest Ultralytics YOLOv8 API.
    results = model.train(
        data=str(DATASET_PATH),
        epochs=EPOCHS,
        imgsz=IMGSZ,
        batch=BATCH,
        workers=WORKERS,
        project=PROJECT,
        name=NAME,
    )

    print("\n[VectorTrack AI] Training completed successfully.")
    print(f"[VectorTrack AI] Training artifacts saved to: {PROJECT}/{NAME}")
    print(f"[VectorTrack AI] Best model summary: {results}")


if __name__ == "__main__":
    main()
