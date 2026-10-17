const fs = require('fs');
const path = require('path');

const srcDir = path.join(__dirname, '../src/db/migrations');
const destDir = path.join(__dirname, '../dist/src/db/migrations');

if (fs.existsSync(srcDir)) {
  fs.mkdirSync(destDir, { recursive: true });
  const files = fs.readdirSync(srcDir).filter((f) => f.endsWith('.sql'));
  for (const file of files) {
    fs.copyFileSync(path.join(srcDir, file), path.join(destDir, file));
  }
  console.log(`[Build] Copied ${files.length} SQL migration files to dist/src/db/migrations`);
} else {
  console.warn(`[Build] Source migrations directory not found at ${srcDir}`);
}
