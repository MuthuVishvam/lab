const sharp = require('sharp');
const { Storage } = require('@google-cloud/storage');
const path = require('path');
const os = require('os');

const storage = new Storage();

exports.thumbnail = async (event, context) => {
  const bucketName = event.bucket;
  const filePath = event.name;
  const fileName = path.basename(filePath);
  const bucket = storage.bucket(bucketName);

  if (fileName.startsWith('thumb_')) {
    console.log('Already a thumbnail, skipping.');
    return;
  }

  const tempFilePath = path.join(os.tmpdir(), fileName);
  await bucket.file(filePath).download({ destination: tempFilePath });
  console.log(`Downloaded ${filePath} to ${tempFilePath}`);

  const thumbFilePath = path.join(os.tmpdir(), 'thumb_' + fileName);
  await sharp(tempFilePath)
    .resize(200)
    .toFile(thumbFilePath);

  await bucket.upload(thumbFilePath, {
    destination: 'thumb_' + fileName,
  });

  console.log('Thumbnail created and uploaded as thumb_' + fileName);
};
