export type Frame = {
  kind: "rgb" | "w";
  data: number[];
};

export type RGB = [number, number, number];

function calculateRedForWFrame(w: number): number {
  const maxW = 255;
  const maxR = 63;
  if (w === 0) {
    return 0;
  }

  const ratio = (maxW - w) / maxW;
  return Math.round(maxR * ratio * ratio);
}

export function rgbPixelsFromFrame(frame: Frame): RGB[] {
  const pixels: RGB[] = [];

  switch (frame.kind) {
    case "rgb":
      for (let i = 0; i < frame.data.length; i += 3) {
        pixels.push([frame.data[i], frame.data[i + 1], frame.data[i + 2]]);
      }
      break;
    case "w":
      for (let i = 0; i < frame.data.length; i += 1) {
        const w = frame.data[i];
        pixels.push([w, w, w]);
      }
      break;
  }

  return pixels;
}
