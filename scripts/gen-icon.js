// Generates assets/tray.png (32px) and build/icon.ico (16/32/48/256) — the 2x2
// tile "start" glyph — with zero dependencies.
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

function drawRGBA(size) {
  const px = Buffer.alloc(size * size * 4);
  const off = Math.max(1, Math.round(size / 32));
  const gap = Math.max(2, Math.round((size * 3) / 32));
  const tile = Math.floor((size - 2 * off - gap) / 2);
  const squares = [
    [off, off], [off + tile + gap, off],
    [off, off + tile + gap], [off + tile + gap, off + tile + gap],
  ];
  for (const [sx, sy] of squares)
    for (let y = sy; y < sy + tile; y++)
      for (let x = sx; x < sx + tile; x++) {
        const i = (y * size + x) * 4;
        px[i] = 76; px[i + 1] = 194; px[i + 2] = 255; px[i + 3] = 255;
      }
  return px;
}

function crc32(buf) {
  if (!crc32.table) {
    crc32.table = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      crc32.table[n] = c;
    }
  }
  let c = 0xFFFFFFFF;
  for (const b of buf) c = crc32.table[(c ^ b) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

function chunk(type, data) {
  const t = Buffer.from(type, 'ascii');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([len, t, data, crc]);
}

function pngOf(size) {
  const px = drawRGBA(size);
  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0; // filter: none
    px.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // color type RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ICO container with PNG-compressed entries (valid on Vista+).
function icoOf(sizes) {
  const pngs = sizes.map(pngOf);
  const header = Buffer.alloc(6);
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(sizes.length, 4);
  const entries = [];
  let offset = 6 + 16 * sizes.length;
  for (let i = 0; i < sizes.length; i++) {
    const e = Buffer.alloc(16);
    e[0] = sizes[i] === 256 ? 0 : sizes[i]; // width (0 = 256)
    e[1] = sizes[i] === 256 ? 0 : sizes[i]; // height
    e.writeUInt16LE(1, 4);  // planes
    e.writeUInt16LE(32, 6); // bpp
    e.writeUInt32LE(pngs[i].length, 8);
    e.writeUInt32LE(offset, 12);
    offset += pngs[i].length;
    entries.push(e);
  }
  return Buffer.concat([header, ...entries, ...pngs]);
}

function write(rel, buf) {
  const out = path.join(__dirname, '..', rel);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, buf);
  console.log('wrote ' + out);
}

write('assets/tray.png', pngOf(32));
write('build/icon.ico', icoOf([16, 32, 48, 256]));
