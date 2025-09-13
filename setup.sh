#!/bin/bash
set -e

# Variables
PROJECT_ID=$(gcloud config get-value project)
REGION=us-west1
BUCKET=qwiklabs-gcp-00-7082c3ae08c4-bucket
FUNCTION_NAME=memories-thumbnail-creator
PREV_ENGINEER="student-01-128a50f6970a@qwiklabs.net"

echo "✅ Enabling required APIs..."
gcloud services enable \
  cloudfunctions.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  pubsub.googleapis.com \
  storage.googleapis.com

echo "✅ Removing old function if it exists..."
gcloud functions delete $FUNCTION_NAME --region=$REGION --gen2 --quiet || true

echo "✅ Preparing function source..."
rm -rf ~/thumbnail-func && mkdir ~/thumbnail-func && cd ~/thumbnail-func

# index.js
cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');
const { Storage } = require('@google-cloud/storage');
const { PubSub } = require('@google-cloud/pubsub');
const sharp = require('sharp');

functions.cloudEvent('memories-thumbnail-creator', async cloudEvent => {
  const event = cloudEvent.data;
  console.log(`Event: ${JSON.stringify(event)}`);

  const fileName = event.name;
  const bucketName = event.bucket;
  const bucket = new Storage().bucket(bucketName);
  const topicName = "topic-memories-357";
  const pubsub = new PubSub();

  if (fileName.search("64x64_thumbnail") === -1) {
    const filename_split = fileName.split('.');
    const filename_ext = filename_split[filename_split.length - 1].toLowerCase();
    const filename_without_ext = fileName.substring(0, fileName.length - filename_ext.length - 1);

    if (filename_ext === 'png' || filename_ext === 'jpg' || filename_ext === 'jpeg') {
      console.log(`Processing Original: gs://${bucketName}/${fileName}`);
      const gcsObject = bucket.file(fileName);
      const newFilename = `${filename_without_ext}_64x64_thumbnail.${filename_ext}`;
      const gcsNewObject = bucket.file(newFilename);

      try {
        const [buffer] = await gcsObject.download();
        const resizedBuffer = await sharp(buffer)
          .resize(64, 64, { fit: 'inside', withoutEnlargement: true })
          .toFormat(filename_ext)
          .toBuffer();

        await gcsNewObject.save(resizedBuffer, {
          metadata: { contentType: `image/${filename_ext}` },
        });

        console.log(`Success: ${fileName} → ${newFilename}`);

        await pubsub.topic(topicName).publishMessage({ data: Buffer.from(newFilename) });

        console.log(`Message published to ${topicName}`);
      } catch (err) {
        console.error(`Error: ${err}`);
      }
    } else {
      console.log(`gs://${bucketName}/${fileName} is not an image I can handle`);
    }
  } else {
    console.log(`gs://${bucketName}/${fileName} already has a thumbnail`);
  }
});
EOF

# package.json
cat > package.json <<'EOF'
{
 "name": "thumbnails",
 "version": "1.0.0",
 "description": "Create Thumbnail of uploaded image",
 "scripts": {
   "start": "node index.js"
 },
 "dependencies": {
   "@google-cloud/functions-framework": "^3.0.0",
   "@google-cloud/pubsub": "^2.0.0",
   "@google-cloud/storage": "^6.11.0",
   "sharp": "^0.32.1"
 },
 "devDependencies": {},
 "engines": {
   "node": ">=4.3.2"
 }
}
EOF

echo "✅ Deploying Cloud Run Function..."
gcloud functions deploy $FUNCTION_NAME \
  --gen2 \
  --runtime=nodejs22 \
  --region=$REGION \
  --entry-point=memories-thumbnail-creator \
  --trigger-bucket=$BUCKET \
  --allow-unauthenticated

echo "✅ Removing previous cloud engineer from project..."
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="user:$PREV_ENGINEER" \
  --role="roles/viewer" \
  --quiet || true

echo "🎉 All tasks (3 & 4) completed successfully!"
