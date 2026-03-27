#!/usr/bin/env node
/**
 * Generate launcher icons for all mipmap densities, Play Store icon (512x512),
 * and feature graphic (1024x500).
 *
 * Usage: node scripts/generate-icons.js
 * Requires: npm install sharp
 */
const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

const RES_DIR = path.join(__dirname, '..', 'app', 'src', 'main', 'res');
const PLAY_STORE_DIR = path.join(__dirname, '..', 'playstore-graphics');

// Mipmap density sizes (px) for launcher icons
const DENSITIES = {
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

const GREEN = '#22C55E';
const WHITE = '#FFFFFF';

// SVG for square launcher icon (green bg + white checkmark)
function launcherSvg(size) {
  const scale = size / 108;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 108 108">
  <rect width="108" height="108" fill="${GREEN}" rx="16"/>
  <path fill="${WHITE}" d="M44,58L38,52C37.2,51.2 37.2,49.8 38,49C38.8,48.2 40.2,48.2 41,49L46,54L67,33C67.8,32.2 69.2,32.2 70,33C70.8,33.8 70.8,35.2 70,36L48,58C47.2,58.8 44.8,58.8 44,58Z"/>
</svg>`;
}

// SVG for round launcher icon (green circle bg + white checkmark)
function roundLauncherSvg(size) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 108 108">
  <circle cx="54" cy="54" r="54" fill="${GREEN}"/>
  <path fill="${WHITE}" d="M44,58L38,52C37.2,51.2 37.2,49.8 38,49C38.8,48.2 40.2,48.2 41,49L46,54L67,33C67.8,32.2 69.2,32.2 70,33C70.8,33.8 70.8,35.2 70,36L48,58C47.2,58.8 44.8,58.8 44,58Z"/>
</svg>`;
}

// SVG for Play Store icon (512x512, rounded corners per Play Store spec)
function playStoreIconSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <rect width="512" height="512" fill="${GREEN}" rx="76"/>
  <path fill="${WHITE}" transform="translate(128, 128) scale(2.37)" d="M44,58L38,52C37.2,51.2 37.2,49.8 38,49C38.8,48.2 40.2,48.2 41,49L46,54L67,33C67.8,32.2 69.2,32.2 70,33C70.8,33.8 70.8,35.2 70,36L48,58C47.2,58.8 44.8,58.8 44,58Z"/>
</svg>`;
}

// SVG for feature graphic (1024x500)
function featureGraphicSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#16A34A"/>
      <stop offset="100%" stop-color="#22C55E"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <!-- Checkmark icon -->
  <g transform="translate(362, 80) scale(3.5)">
    <path fill="rgba(255,255,255,0.2)" d="M44,58L38,52C37.2,51.2 37.2,49.8 38,49C38.8,48.2 40.2,48.2 41,49L46,54L67,33C67.8,32.2 69.2,32.2 70,33C70.8,33.8 70.8,35.2 70,36L48,58C47.2,58.8 44.8,58.8 44,58Z"/>
  </g>
  <!-- App name -->
  <text x="512" y="310" text-anchor="middle" font-family="sans-serif" font-weight="bold" font-size="80" fill="${WHITE}">Wellvo</text>
  <!-- Tagline -->
  <text x="512" y="380" text-anchor="middle" font-family="sans-serif" font-weight="400" font-size="32" fill="rgba(255,255,255,0.9)">One tap. Peace of mind.</text>
</svg>`;
}

async function main() {
  // Create Play Store graphics directory
  fs.mkdirSync(PLAY_STORE_DIR, { recursive: true });

  // Generate mipmap density PNGs
  for (const [folder, size] of Object.entries(DENSITIES)) {
    const dir = path.join(RES_DIR, folder);
    fs.mkdirSync(dir, { recursive: true });

    // Square icon
    await sharp(Buffer.from(launcherSvg(size)))
      .resize(size, size)
      .png()
      .toFile(path.join(dir, 'ic_launcher.png'));

    // Round icon
    await sharp(Buffer.from(roundLauncherSvg(size)))
      .resize(size, size)
      .png()
      .toFile(path.join(dir, 'ic_launcher_round.png'));

    console.log(`  ${folder}: ${size}x${size} ✓`);
  }

  // Play Store icon (512x512)
  await sharp(Buffer.from(playStoreIconSvg()))
    .resize(512, 512)
    .png()
    .toFile(path.join(PLAY_STORE_DIR, 'icon-512.png'));
  console.log('  Play Store icon: 512x512 ✓');

  // Feature graphic (1024x500)
  await sharp(Buffer.from(featureGraphicSvg()))
    .resize(1024, 500)
    .png()
    .toFile(path.join(PLAY_STORE_DIR, 'feature-graphic.png'));
  console.log('  Feature graphic: 1024x500 ✓');

  console.log('\nDone! Icons generated in:');
  console.log(`  Mipmaps: ${RES_DIR}/mipmap-*/`);
  console.log(`  Play Store: ${PLAY_STORE_DIR}/`);
}

main().catch((err) => {
  console.error('Error generating icons:', err);
  process.exit(1);
});
