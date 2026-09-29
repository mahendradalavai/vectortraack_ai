"""Run YOLO inference on test images for VectorTrack AI.

Loads the trained model from ``models/best.pt``, runs detection on every
image in ``images/``, prints results, saves annotated images to ``output/``,
and displays each result in an OpenCV window.
"""

from pathlib import Path

import cv2
from ultralytics import YOLO

from supabase_client import save_detection_for_dev_user


MODEL_PATH = Path("models/best.pt")
IMAGES_DIR = Path("images")
OUTPUT_DIR = Path("output")
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def get_test_images() -> list[Path]:
    """Collect supported image files from the images folder."""
    if not IMAGES_DIR.exists():
        raise FileNotFoundError(
            f"Images folder not found: {IMAGES_DIR.resolve()}. "
            "Please add test images before running inference."
        )

    images = sorted(
        path for path in IMAGES_DIR.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
    )

    if not images:
        raise FileNotFoundError(
            f"No test images found in {IMAGES_DIR.resolve()}. "
            f"Supported formats: {', '.join(sorted(IMAGE_EXTENSIONS))}"
        )

    return images


def main() -> None:
    """Run inference on all test images and show the results."""
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Model file not found: {MODEL_PATH.resolve()}. "
            "Copy your trained weights to models/best.pt first."
        )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("\n[VectorTrack AI] Loading trained model...")
    model = YOLO(str(MODEL_PATH))

    test_images = get_test_images()
    print(f"[VectorTrack AI] Found {len(test_images)} test image(s).\n")

    for image_path in test_images:
        print(f"[VectorTrack AI] Processing: {image_path.name}")

        # Run inference on the current image.
        results = model(str(image_path))

        print("Detected:")
        detections_found = False

        for result in results:
            boxes = result.boxes
            if boxes is None or len(boxes) == 0:
                continue

            detections_found = True
            for box in boxes:
                class_id = int(box.cls[0])
                class_name = model.names[class_id]
                confidence = float(box.conf[0])
                print(f"  {class_name} {confidence:.2f}")
                save_detection_for_dev_user(
                    class_name=class_name,
                    confidence=confidence,
                    image_name=image_path.name,
                    image_path=str(image_path),
                    source="image",
                    media_type="image"
                )

        if not detections_found:
            print("  (no objects detected)")

        # Draw bounding boxes, class names, and confidence scores.
        annotated_image = results[0].plot()

        output_path = OUTPUT_DIR / f"result_{image_path.stem}.jpg"
        cv2.imwrite(str(output_path), annotated_image)
        print(f"[VectorTrack AI] Saved result to: {output_path}\n")

        # Display the annotated image; press any key to continue.
        window_title = f"VectorTrack AI - {image_path.name}"
        try:
            cv2.imshow(window_title, annotated_image)
            print("[VectorTrack AI] Press any key in the image window to continue...")
            cv2.waitKey(0)
            cv2.destroyAllWindows()
        except cv2.error:
            print("[VectorTrack AI] Display skipped (no GUI available).")

    print("[VectorTrack AI] All test images processed successfully.")


if __name__ == "__main__":
    main()
