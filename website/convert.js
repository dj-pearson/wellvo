import sharp from 'sharp';

const svgPath = 'public/favicon.svg';

async function generate() {
    const iconPaths = [
        { file: 'public/icon-16.png', size: 16 },
        { file: 'public/icon-32.png', size: 32 },
        { file: 'public/icon-192.png', size: 192 },
        { file: 'public/icon-512.png', size: 512 },
        { file: 'public/apple-touch-icon.png', size: 180 },
        { file: '../ios/Wellvo/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png', size: 1024 }
    ];

    for (const { file, size } of iconPaths) {
        await sharp(svgPath)
            .resize(size, size)
            .png()
            .toFile(file);
        console.log(`Generated ${file} (${size}x${size})`);
    }
}

generate().catch(console.error);
