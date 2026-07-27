import datetime
from pathlib import Path
import firebase_admin
from firebase_admin import credentials, firestore

# Path to the service account key in the project root, resolved relative to this file
SERVICE_ACCOUNT_KEY = Path(__file__).resolve().parent / "serviceAccountKey.json"


# Initialize firebase admin sdk
if not firebase_admin._apps:
    if SERVICE_ACCOUNT_KEY.exists():
        cred = credentials.Certificate(str(SERVICE_ACCOUNT_KEY))
        firebase_admin.initialize_app(cred)
    else:
        raise FileNotFoundError(
            f"Firebase service account key not found at {SERVICE_ACCOUNT_KEY.resolve()}. "
            "Please place serviceAccountKey.json in the project root before running detection."
        )

# Initialize Firestore client
db = firestore.client()

def save_detection(
    class_name: str,
    confidence: float,
    image_name: str,
    image_path: str,
    source: str
) -> None:
    """Saves a detection to the Firestore collection named 'detections'."""
    try:
        doc_ref = db.collection("detections").document()
        doc_data = {
            "class": class_name,
            "confidence": confidence,
            "timestamp": firestore.SERVER_TIMESTAMP,
            "image_name": image_name,
            "image_path": image_path,
            "source": source
        }
        doc_ref.set(doc_data)
        print("[Firebase] Detection uploaded successfully.")
    except Exception as e:
        print(f"[Firebase] Error uploading detection: {e}")
