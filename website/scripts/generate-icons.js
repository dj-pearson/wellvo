import sharp from 'sharp';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const publicDir = join(__dirname, '..', 'public');
const svgBuffer = readFileSync(join(publicDir, 'favicon.svg'));

const iconSizes = [
  { name: 'icon-16.png', size: 16 },
  { name: 'icon-32.png', size: 32 },
  { name: 'icon-192.png', size: 192 },
  { name: 'icon-512.png', size: 512 },
  { name: 'apple-touch-icon.png', size: 180 },
];

async function generateIcons() {
  for (const { name, size } of iconSizes) {
    await sharp(svgBuffer)
      .resize(size, size)
      .png()
      .toFile(join(publicDir, name));
    console.log(`Generated ${name} (${size}x${size})`);
  }
}

async function generateOgImage() {
  const width = 1200;
  const height = 630;

  // Create an SVG overlay with text on a green gradient background
  const svgOverlay = `
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" style="stop-color:#2ECC71;stop-opacity:1" />
          <stop offset="100%" style="stop-color:#27AE60;stop-opacity:1" />
        </linearGradient>
      </defs>
      <rect width="${width}" height="${height}" fill="url(#bg)" />
      <text x="600" y="270" font-family="system-ui, sans-serif" font-size="96" font-weight="bold" text-anchor="middle" fill="white">Wellvo</text>
      <text x="600" y="370" font-family="system-ui, sans-serif" font-size="36" text-anchor="middle" fill="rgba(255,255,255,0.9)">One tap. Peace of mind.</text>
    </svg>
  `;

  await sharp(Buffer.from(svgOverlay))
    .resize(width, height)
    .png()
    .toFile(join(publicDir, 'og-image.png'));
  console.log(`Generated og-image.png (${width}x${height})`);
}

await generateIcons();
await generateOgImage();
console.log('All icons generated successfully!');
