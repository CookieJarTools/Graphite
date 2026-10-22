// Draws Home's backdrop (its colour plus the soft glow, as home.css lays them out) pixel by
// pixel with dithering. The glow spans only a few shades, so drawn plainly in 8-bit colour
// it shows as rings; spreading each pixel's rounding as a little noise hides them, as in a
// well-made photograph of a gradient. main.js sizes the page in physical pixels and passes
// the screen's scale so the glow keeps Home's size.

const scale = Number(new URLSearchParams(location.search).get('scale')) || 1;
const canvas = document.getElementById('backdrop');
// In device pixels, whatever the page's own scale, so every pixel gets its own noise.
const width = Math.round(window.innerWidth * devicePixelRatio);
const height = Math.round(window.innerHeight * devicePixelRatio);
canvas.width = width;
canvas.height = height;

function rgb(cssColor) {
  const hex = cssColor.trim().replace('#', '');
  return [0, 2, 4].map((at) => parseInt(hex.slice(at, at + 2), 16));
}

const style = getComputedStyle(document.documentElement);
const base = rgb(style.getPropertyValue('--backdrop'));
const glow = rgb(style.getPropertyValue('--backdrop-glow'));

// home.css: a 1400 x 960 box centred at 50% / 40%, filled with
// radial-gradient(ellipse at center, glow, transparent 65%). The ellipse reaches the box's
// corners, so its radii are the half-sizes times the square root of two.
const centreX = width / 2;
const centreY = height * 0.4;
const radiusX = 700 * Math.SQRT2 * scale;
const radiusY = 480 * Math.SQRT2 * scale;
const stop = 0.65;

const image = new ImageData(width, height);
const pixels = image.data;
for (let y = 0; y < height; y++) {
  const dy = (y + 0.5 - centreY) / radiusY;
  for (let x = 0; x < width; x++) {
    const dx = (x + 0.5 - centreX) / radiusX;
    const amount = Math.max(0, 1 - Math.sqrt(dx * dx + dy * dy) / stop);
    // Triangular noise of one shade either way: the rounding error turns into grain.
    const noise = Math.random() - Math.random();
    const at = (y * width + x) * 4;
    for (let channel = 0; channel < 3; channel++) {
      const value = base[channel] + (glow[channel] - base[channel]) * amount + noise;
      pixels[at + channel] = Math.max(0, Math.min(255, Math.round(value)));
    }
    pixels[at + 3] = 255;
  }
}
canvas.getContext('2d').putImageData(image, 0, 0);
document.body.dataset.ready = '1';
