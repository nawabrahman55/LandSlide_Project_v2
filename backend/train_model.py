"""
Landslide Early Warning System (LEWS) - Model Training Pipeline
Trains a Scikit-Learn RandomForestClassifier with StandardScaler normalization
on physical landslide trigger features and serializes the model to joblib.
"""

import os
import json
from datetime import datetime, timezone
import numpy as np
import pandas as pd
import joblib

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier
from sklearn.pipeline import Pipeline
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score, accuracy_score

from dataset_loader import load_dataset, get_features_and_target, FEATURE_COLUMNS, TARGET_COLUMN

# Target artifact paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(BASE_DIR, "models")
MODEL_OUTPUT_PATH = os.path.join(MODELS_DIR, "landslide_rf.joblib")


def train_landslide_pipeline(
    csv_path: str = None,
    output_path: str = MODEL_OUTPUT_PATH,
    random_state: int = 42
) -> Pipeline:
    """
    Trains and evaluates the Landslide Risk Random Forest classifier.
    
    Pipeline Steps:
      1. Load dataset (NASA GLC or regional rainfall-induced dataset)
      2. Train/Test split (80/20 stratified)
      3. StandardScaler normalization
      4. RandomForestClassifier training
      5. Full metric evaluation (Precision, Recall, F1, ROC-AUC)
      6. Serialization to joblib
    """
    print("=" * 65)
    print("LEWS Machine Learning Pipeline: RandomForestClassifier Training")
    print("=" * 65)
    
    # 1. Load dataset
    print(f"\n[1/5] Loading landslide trigger dataset...")
    df = load_dataset(csv_path)
    X, y = get_features_and_target(df)
    print(f" -> Total dataset size: {len(df)} samples")
    print(f" -> Feature matrix shape: {X.shape} (Features: {FEATURE_COLUMNS})")
    print(f" -> Target counts: 0 (Safe)={sum(y==0)}, 1 (Landslide)={sum(y==1)}")
    
    # 2. Train-Test Split (Strict featurization ordering: split BEFORE fitting scaler)
    print(f"\n[2/5] Splitting dataset into training (80%) and test (20%) sets...")
    X_train, X_test, y_train, y_test = train_test_split(
        X, y,
        test_size=0.20,
        random_state=random_state,
        stratify=y
    )
    print(f" -> Train set: {X_train.shape[0]} samples")
    print(f" -> Test set:  {X_test.shape[0]} samples")
    
    # 3. Create Pipeline with StandardScaler and RandomForestClassifier
    print(f"\n[3/5] Initializing normalization scaler and Random Forest model...")
    scaler = StandardScaler()
    rf = RandomForestClassifier(
        n_estimators=100,
        max_depth=12,
        min_samples_split=4,
        min_samples_leaf=2,
        class_weight="balanced",
        random_state=random_state,
        n_jobs=-1
    )
    
    pipeline = Pipeline(steps=[
        ("scaler", scaler),
        ("classifier", rf)
    ])
    
    # 4. Train
    print("[4/5] Fitting StandardScaler and training RandomForestClassifier...")
    pipeline.fit(X_train, y_train)
    print(" -> Model training complete!")
    
    # 5. Evaluate on Test Set
    print("\n[5/5] Evaluating model performance on held-out test data...")
    y_pred = pipeline.predict(X_test)
    y_proba = pipeline.predict_proba(X_test)[:, 1]
    
    acc = accuracy_score(y_test, y_pred)
    roc_auc = roc_auc_score(y_test, y_proba)
    cm = confusion_matrix(y_test, y_pred)
    report_text = classification_report(
        y_test, y_pred,
        target_names=["Safe / Stable (0)", "Landslide Triggered (1)"],
        digits=4
    )
    report_dict = classification_report(
        y_test, y_pred,
        target_names=["Safe / Stable (0)", "Landslide Triggered (1)"],
        output_dict=True
    )
    
    print("\n" + "-" * 65)
    print("CLASSIFICATION REPORT (Precision, Recall, F1-Score)")
    print("-" * 65)
    print(report_text)
    print(f"Test Accuracy: {acc * 100:.2f}%")
    print(f"ROC-AUC Score: {roc_auc:.4f}")
    print("-" * 65)
    print("CONFUSION MATRIX:")
    print(f" [[True Negatives (Safe):      {cm[0, 0]:4d}, False Positives: {cm[0, 1]:4d}],")
    print(f"  [False Negatives (Missed):   {cm[1, 0]:4d}, True Positives:  {cm[1, 1]:4d}]]")
    print("-" * 65)
    
    # Feature importances
    feature_importances = rf.feature_importances_
    print("\nFEATURE IMPORTANCES:")
    for feat, imp in sorted(zip(FEATURE_COLUMNS, feature_importances), key=lambda x: x[1], reverse=True):
        bar = "#" * int(imp * 30)
        print(f" - {feat:15s}: {imp:6.4f} ({imp*100:5.1f}%) {bar}")
    
    # Attach helpful metadata to pipeline object
    pipeline.feature_names_ = FEATURE_COLUMNS
    pipeline.metrics_ = {
        "accuracy": acc,
        "roc_auc": roc_auc,
        "classification_report": report_dict,
        "confusion_matrix": cm.tolist(),
        "trained_at": datetime.now(timezone.utc).isoformat()
    }
    
    # 6. Serialize model artifact
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    joblib.dump(pipeline, output_path)
    file_size_kb = os.path.getsize(output_path) / 1024
    print(f"\n[OK] Trained model successfully serialized to:")
    print(f"     Path: {output_path}")
    print(f"     Size: {file_size_kb:.1f} KB")
    print("=" * 65)
    
    return pipeline


if __name__ == "__main__":
    train_landslide_pipeline()
