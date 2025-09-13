#!/bin/bash
set -e

# Config
REGION=us-west1
FUNCTION_NAME=memories-thumbnail-creator
BUCKET=qwiklabs-gcp-00-7082c3ae08c4-bucket

echo "✅ Enabling required APIs..."
gcloud services enable cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com

echo "✅ Removing old function if it exists..."
gcloud functions delete $FUNCTION_NAME --region=$REGION --gen2 --quiet || true

echo "✅ Preparing function source..."
mkdir -p thumbnail-func
cd thumbnail-func

# Create package.json
cat > package.json <<EOF
{
  "name": "thumbnail-func",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "sharp": "^0.32.1"
  }
}
EOF

# Create index.js
cat > index.js <<EOF
const sharp = require('sharp');
const { Storage } = require('@google-cloud/storage');
const path = require('path');
const os = require('os');
const fs = require('fs');

const storage = new Storage();
exports.thumbnail = async (event, context) => {
  const bucketName = event.bucket;
  const filePath = event.name;
  const fileName = path.basename(filePath);
  const bucket = storage.bucket(bucketName);

  if (fileName.startsWith('thumb_')) {
    console.log('Already a thumbnail.');
    return;
  }

  const tempFilePath = path.join(os.tmpdir(), fileName);
  await bucket.file(filePath).download({ destination: tempFilePath });
  console.log(\`Image downloaded locally to \${tempFilePath}\`);

  const thumbFilePath = path.join(os.tmpdir(), 'thumb_' + fileName);
  await sharp(tempFilePath)
    .resize(200)
    .toFile(thumbFilePath);

  await bucket.upload(thumbFilePath, {
    destination: 'thumb_' + fileName,
  });

  console.log('Thumbnail created and uploaded.');
};
EOF

cd ..

echo "✅ Deploying Cloud Function..."
gcloud functions deploy $FUNCTION_NAME \
  --gen2 \
  --runtime=nodejs16 \
  --region=$REGION \
  --entry-point=thumbnail \
  --trigger-bucket=$BUCKET \
  --allow-unauthenticated

