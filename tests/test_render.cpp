// csARM visual test: renders a real frame on aarch64 using the ported
// mathlib (Vector/Matrix3x4/QAngle paths compiled from c15/mathlib with the
// NEON patches), software-rasterizes it, and writes a PNG.
// Success criteria (checked by CI): PNG exists, magic + IEND valid, size > 20K.
#include "mathlib/mathlib.h"
#include "mathlib/mathlib.h"
#include "tier0/basetypes.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

// ---------- minimal PNG writer (zlib stored blocks, crc32) ----------
static uint32_t crc_table[256];
static void crc_init(void) {
  for (uint32_t n = 0; n < 256; n++) {
    uint32_t c = n;
    for (int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
    crc_table[n] = c;
  }
}
static uint32_t crc32_buf(const uint8_t *b, size_t n) {
  uint32_t c = 0xFFFFFFFFu;
  for (size_t i = 0; i < n; i++) c = crc_table[(c ^ b[i]) & 0xFF] ^ (c >> 8);
  return c ^ 0xFFFFFFFFu;
}
static void chunk(FILE *f, const char *type, const uint8_t *data, size_t n) {
  uint8_t len[4] = { (uint8_t)(n >> 24), (uint8_t)(n >> 16), (uint8_t)(n >> 8), (uint8_t)n };
  fwrite(len, 1, 4, f);
  fwrite(type, 1, 4, f);
  if (n) fwrite(data, 1, n, f);
  uint8_t crcb[4];
  uint32_t c = crc32_buf((const uint8_t *)type, 4);
  // crc over type+data
  crc32_buf((const uint8_t *)type, 4); // (stateless helper: recompute below)
  // build full buffer for crc
  uint8_t *tmp = (uint8_t *)malloc(4 + n);
  memcpy(tmp, type, 4);
  if (n) memcpy(tmp + 4, data, n);
  c = crc32_buf(tmp, 4 + n);
  free(tmp);
  crcb[0] = (uint8_t)(c >> 24); crcb[1] = (uint8_t)(c >> 16);
  crcb[2] = (uint8_t)(c >> 8);  crcb[3] = (uint8_t)c;
  fwrite(crcb, 1, 4, f);
}
static uint32_t adler32_buf(const uint8_t *b, size_t n) {
  uint32_t a = 1, s = 0;
  for (size_t i = 0; i < n; i++) {
    a = (a + b[i]) % 65521;
    s = (s + a) % 65521;
  }
  return (s << 16) | a;
}
static int write_png(const char *path, const uint8_t *rgb, int w, int h) {
  FILE *f = fopen(path, "wb");
  if (!f) return -1;
  static const uint8_t sig[8] = { 137, 'P', 'N', 'G', 13, 10, 26, 10 };
  fwrite(sig, 1, 8, f);
  // IHDR
  uint8_t ihdr[13];
  ihdr[0] = (uint8_t)(w >> 24); ihdr[1] = (uint8_t)(w >> 16);
  ihdr[2] = (uint8_t)(w >> 8);  ihdr[3] = (uint8_t)w;
  ihdr[4] = (uint8_t)(h >> 24); ihdr[5] = (uint8_t)(h >> 16);
  ihdr[6] = (uint8_t)(h >> 8);  ihdr[7] = (uint8_t)h;
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 2;   // color type RGB
  ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  chunk(f, "IHDR", ihdr, 13);
  // IDAT: zlib stream with stored (uncompressed) deflate blocks
  size_t rawlen = (size_t)h * (1 + (size_t)w * 3);
  uint8_t *raw = (uint8_t *)malloc(rawlen);
  for (int y = 0; y < h; y++) {
    uint8_t *row = raw + (size_t)y * (1 + (size_t)w * 3);
    row[0] = 0;  // filter none
    memcpy(row + 1, rgb + (size_t)y * (size_t)w * 3, (size_t)w * 3);
  }
  size_t zlen = rawlen + rawlen / 65536 * 5 + 64;
  uint8_t *z = (uint8_t *)malloc(zlen);
  size_t zp = 0;
  z[zp++] = 0x78; z[zp++] = 0x01;  // zlib header, fastest
  size_t off = 0;
  while (off < rawlen) {
    size_t blk = rawlen - off; if (blk > 65535) blk = 65535;
    int last = (off + blk == rawlen);
    z[zp++] = last ? 1 : 0;
    z[zp++] = (uint8_t)(blk & 0xFF); z[zp++] = (uint8_t)(blk >> 8);
    z[zp++] = (uint8_t)(~blk & 0xFF); z[zp++] = (uint8_t)((~blk >> 8) & 0xFF);
    memcpy(z + zp, raw + off, blk); zp += blk; off += blk;
  }
  uint32_t ad = adler32_buf(raw, rawlen);
  z[zp++] = (uint8_t)(ad >> 24); z[zp++] = (uint8_t)(ad >> 16);
  z[zp++] = (uint8_t)(ad >> 8);  z[zp++] = (uint8_t)ad;
  chunk(f, "IDAT", z, zp);
  chunk(f, "IEND", NULL, 0);
  fclose(f);
  free(raw); free(z);
  return 0;
}

// ---------- software rasterizer ----------
#define W 480
#define H 320
static uint8_t fb[H][W][3];

static void clear_bg(float t) {
  for (int y = 0; y < H; y++)
    for (int x = 0; x < W; x++) {
      fb[y][x][0] = (uint8_t)(16 + 10 * (0.5f + 0.5f * sinf(t * 0.7f + x * 0.01f)));
      fb[y][x][1] = (uint8_t)(18 + 12 * (0.5f + 0.5f * sinf(t * 1.1f + y * 0.013f)));
      fb[y][x][2] = (uint8_t)(26 + 16 * (0.5f + 0.5f * sinf(t * 1.3f + (x + y) * 0.007f)));
    }
}

// rotate+translate a local-space triangle through a Matrix3x4 built from
// the ported QAngle->Matrix path, project perspective, rasterize with a
// barycentric fill
static void draw_tri(const Vector &v0, const Vector &v1, const Vector &v2,
                     const matrix3x4_t &xf, float r, float g, float b) {
  Vector p0, p1, p2;
  VectorTransform(v0, xf, p0);
  VectorTransform(v1, xf, p1);
  VectorTransform(v2, xf, p2);
  const float camz = 3.0f;
  auto proj = [&](const Vector &p, float *sx, float *sy) {
    float z = camz - p.z;
    if (z < 0.1f) z = 0.1f;
    *sx = (p.x / z) * 280.0f + W * 0.5f;
    *sy = (-p.y / z) * 280.0f + H * 0.5f;
  };
  float x0, y0, x1, y1, x2, y2;
  proj(p0, &x0, &y0); proj(p1, &x1, &y1); proj(p2, &x2, &y2);
  float minx = fmaxf(0.f, floorf(fminf(fminf(x0, x1), x2)));
  float maxx = fminf(W - 1.f, ceilf(fmaxf(fmaxf(x0, x1), x2)));
  float miny = fmaxf(0.f, floorf(fminf(fminf(y0, y1), y2)));
  float maxy = fminf(H - 1.f, ceilf(fmaxf(fmaxf(y0, y1), y2)));
  float d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2);
  if (fabsf(d) < 1e-6f) return;
  for (int y = (int)miny; y <= (int)maxy; y++)
    for (int x = (int)minx; x <= (int)maxx; x++) {
      float px = x + 0.5f, py = y + 0.5f;
      float w0 = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / d;
      float w1 = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / d;
      float w2 = 1.f - w0 - w1;
      if (w0 >= 0 && w1 >= 0 && w2 >= 0) {
        float depth = 1.f - fminf(1.f, fmaxf(0.f, (w0 * p0.z + w1 * p1.z + w2 * p2.z + 1.2f) / 2.4f));
        fb[y][x][0] = (uint8_t)(fb[y][x][0] * (1 - depth) + 255 * r * depth);
        fb[y][x][1] = (uint8_t)(fb[y][x][1] * (1 - depth) + 255 * g * depth);
        fb[y][x][2] = (uint8_t)(fb[y][x][2] * (1 - depth) + 255 * b * depth);
      }
    }
}

int main(void) {
  crc_init();
  const float t = 0.8f;

  // exercise the ported math core explicitly (these run the aarch64/NEON
  // branches patched into c15/mathlib)
  QAngle ang(t * 20.0f, t * 35.0f, 0.0f);
  matrix3x4_t xf;
  AngleMatrix(ang, xf);            // ported AngleMatrix (ARM path)
  Vector axis(0.45f, 0.6f, 1.0f);
  float len = VectorNormalize(axis);   // ported VectorNormalize
  // Valve API: returns the length BEFORE normalization; vector becomes unit
  float pre = sqrtf(0.45f * 0.45f + 0.6f * 0.6f + 1.0f);
  if (fabsf(len - pre) > 1e-3f || fabsf(axis.Length() - 1.0f) > 1e-3f) {
    printf("VISUAL_FAIL VectorNormalize len=%f expected=%f nowlen=%f\n",
           (double)len, (double)pre, (double)axis.Length());
    return 2;
  }

  clear_bg(t);

  // octahedron-ish gem: two apexes + equatorial square, drawn as 8 triangles
  Vector apexN(0, 0.9f, 0), apexS(0, -0.9f, 0);
  Vector ring[4] = { Vector(0.8f, 0, 0.8f), Vector(0.8f, 0, -0.8f),
                     Vector(-0.8f, 0, -0.8f), Vector(-0.8f, 0, 0.8f) };
  const float cols[8][3] = {
    { 0.95f, 0.35f, 0.25f }, { 0.95f, 0.65f, 0.20f },
    { 0.35f, 0.85f, 0.35f }, { 0.25f, 0.75f, 0.90f },
    { 0.55f, 0.40f, 0.95f }, { 0.95f, 0.40f, 0.75f },
    { 0.30f, 0.90f, 0.80f }, { 0.90f, 0.90f, 0.30f },
  };
  int ci = 0;
  for (int i = 0; i < 4; i++) {
    int j = (i + 1) & 3;
    draw_tri(ring[i], ring[j], apexN, xf, cols[ci][0], cols[ci][1], cols[ci][2]); ci++;
    draw_tri(ring[j], ring[i], apexS, xf, cols[ci][0], cols[ci][1], cols[ci][2]); ci++;
  }

  // spinning quad behind (uses VectorTransform again)
  QAngle ang2(-t * 12.0f, 10.0f, t * 8.0f);
  matrix3x4_t xf2;
  AngleMatrix(ang2, xf2);
  Vector q0(-1.6f, -0.8f, -1.2f), q1(1.6f, -0.8f, -1.2f),
         q2(1.6f, 0.8f, -1.2f), q3(-1.6f, 0.8f, -1.2f);
  draw_tri(q0, q1, q2, xf2, 0.16f, 0.20f, 0.45f);
  draw_tri(q0, q2, q3, xf2, 0.12f, 0.16f, 0.38f);

  if (write_png("tests/out/frame.png", &fb[0][0][0], W, H) != 0) {
    printf("VISUAL_FAIL png write\n");
    return 2;
  }
  printf("VISUAL_OK frame.png 480x320 len=%.3f ang=(%f %f %f)\n",
         (double)len, (double)ang.x, (double)ang.y, (double)ang.z);
  return 0;
}
