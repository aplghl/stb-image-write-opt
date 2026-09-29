/* Downstream consumer integration test.
 *
 * A realistic "external application" that only uses the public stb_image_write
 * API: it encodes a deterministic 512x512 RGB image to PNG and JPEG through the
 * in-memory callback interface and reports ns/pixel. Built two ways by run.sh:
 *   stock : upstream header, implementation inline, -O2
 *   fork  : fork header (declarations only) + prebuilt static library
 * The delta is the real drop-in speedup a consumer would see.
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <stdint.h>

#include "stb_image_write.h"

#define W 512
#define H 512

static unsigned long g_bytes;
static void sink(void *context, void *data, int size)
{
   (void)context; (void)data;
   g_bytes += (unsigned long)size;
}

static double now_s(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static void make_image(unsigned char *p)
{
   int x, y;
   for (y = 0; y < H; ++y)
      for (x = 0; x < W; ++x) {
         unsigned char *q = p + ((size_t)y * W + x) * 3;
         double fx = (double)x / W, fy = (double)y / H;
         q[0] = (unsigned char)(128 + 100 * (fx - 0.5) * 2 + 20 * ((x * y) & 7));
         q[1] = (unsigned char)(128 + 100 * (fy - 0.5) * 2);
         q[2] = (unsigned char)(128 + 100 * (fx + fy - 1.0));
      }
}

static double bench(int is_jpg, unsigned char *px, double budget, int repeats)
{
   double best = 1e300;
   int r;
   for (r = 0; r < repeats; ++r) {
      double t0 = now_s(), per;
      long iters, i, single_n = 1;
      double single;
      g_bytes = 0;
      if (is_jpg) stbi_write_jpg_to_func(sink, NULL, W, H, 3, px, 90);
      else        stbi_write_png_to_func(sink, NULL, W, H, 3, px, W * 3);
      t0 = now_s();
      if (is_jpg) stbi_write_jpg_to_func(sink, NULL, W, H, 3, px, 90);
      else        stbi_write_png_to_func(sink, NULL, W, H, 3, px, W * 3);
      single = now_s() - t0;
      if (single <= 0) single = 1e-6;
      iters = (long)(budget / single);
      if (iters < 1) iters = 1;
      if (iters > 200000) iters = 200000;
      t0 = now_s();
      for (i = 0; i < iters; ++i) {
         if (is_jpg) stbi_write_jpg_to_func(sink, NULL, W, H, 3, px, 90);
         else        stbi_write_png_to_func(sink, NULL, W, H, 3, px, W * 3);
      }
      per = (now_s() - t0) / (double)iters;
      if (per < best) best = per;
      (void)single_n;
   }
   return best;
}

int main(void)
{
   unsigned char *px = (unsigned char *)malloc((size_t)W * H * 3);
   double png_ns, jpg_ns;
   if (!px) return 2;
   make_image(px);
   jpg_ns = bench(1, px, 0.15, 5);
   png_ns = bench(0, px, 0.4, 5);
   printf("png,%.4f\n", png_ns * 1e9 / (W * H));
   printf("jpg,%.4f\n", jpg_ns * 1e9 / (W * H));
   free(px);
   return 0;
}
