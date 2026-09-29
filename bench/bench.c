/* Encode throughput benchmark for stb_image_write.
 *
 * usage: bench <input|gen:mode> <format> <comp> <quality> [budget_s] [repeats] [opts]
 *   input   : image file, or "gen:grad|plasma|random|flat"
 *   format  : png | bmp | tga | hdr | jpg
 *   budget_s: target seconds per repeat (default 0.2)
 *   repeats : number of repeats, min is reported (default 5)
 * opts:
 *   --dims WxH --seed N --stride N --incomp N --force-filter N --rle 0|1 --flip 0|1
 *
 * output (CSV): input,format,comp,quality,w,h,bytes,iters,ns_per_encode,
 *               ns_per_pixel,Mpixel_per_s
 *
 * Pin with taskset for stable numbers. NOTE: absolute ns are load-sensitive;
 * use ratios (see harness/bench_vs_upstream.sh).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#include "gen.h"

static unsigned long g_sink;
static void sink_cb(void *context, void *data, int size)
{
   (void)context; (void)data;
   g_sink += (unsigned long)size;
}

static double now_s(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static const char *FMT;
static int CMP, QUAL, STRIDE, FLIP;

static int encode(const void *px, int w, int h)
{
   int rc;
   g_sink = 0;
   if (strcmp(FMT, "hdr") == 0)
      rc = stbi_write_hdr_to_func(sink_cb, NULL, w, h, CMP, (const float *)px);
   else if (strcmp(FMT, "png") == 0)
      rc = stbi_write_png_to_func(sink_cb, NULL, w, h, CMP, px, STRIDE);
   else if (strcmp(FMT, "bmp") == 0)
      rc = stbi_write_bmp_to_func(sink_cb, NULL, w, h, CMP, px);
   else if (strcmp(FMT, "tga") == 0)
      rc = stbi_write_tga_to_func(sink_cb, NULL, w, h, CMP, px);
   else if (strcmp(FMT, "jpg") == 0)
      rc = stbi_write_jpg_to_func(sink_cb, NULL, w, h, CMP, px, QUAL);
   else
      rc = 0;
   return rc;
}

int main(int argc, char **argv)
{
   const char *input;
   double budget = 0.2;
   int repeats = 5;
   int i;
   const char *gen = NULL;
   int gw = 256, gh = 256, seed = 1, incomp = 0, force_filter = -1, rle = -1;
   long fixed_iters = 0;
   int w = 0, h = 0;
   void *px = NULL;
   double best_ns = 1e300;
   long best_iters = 0;
   unsigned long out_bytes = 0;
   double total_px;

   if (argc < 5) {
      fprintf(stderr, "usage: %s <input|gen:mode> <format> <comp> <quality> [budget] [repeats] [opts]\n", argv[0]);
      return 2;
   }
   input = argv[1];
   FMT   = argv[2];
   CMP   = atoi(argv[3]);
   QUAL  = atoi(argv[4]);
   if (argc > 5) budget = atof(argv[5]);
   if (argc > 6) repeats = atoi(argv[6]);

   for (i = 7; i < argc; ++i) {
      if (strcmp(argv[i], "--dims") == 0 && i + 1 < argc) sscanf(argv[++i], "%dx%d", &gw, &gh);
      else if (strcmp(argv[i], "--seed") == 0 && i + 1 < argc) seed = atoi(argv[++i]);
      else if (strcmp(argv[i], "--stride") == 0 && i + 1 < argc) STRIDE = atoi(argv[++i]);
      else if (strcmp(argv[i], "--incomp") == 0 && i + 1 < argc) incomp = atoi(argv[++i]);
      else if (strcmp(argv[i], "--force-filter") == 0 && i + 1 < argc) force_filter = atoi(argv[++i]);
      else if (strcmp(argv[i], "--rle") == 0 && i + 1 < argc) rle = atoi(argv[++i]);
      else if (strcmp(argv[i], "--flip") == 0 && i + 1 < argc) FLIP = atoi(argv[++i]);
      else if (strcmp(argv[i], "--iters") == 0 && i + 1 < argc) fixed_iters = atol(argv[++i]);
      else { fprintf(stderr, "unknown option %s\n", argv[i]); return 2; }
   }
   g_seed = (uint32_t)seed;

   if (force_filter >= 0) stbi_write_force_png_filter = force_filter;
   if (rle >= 0) stbi_write_tga_with_rle = rle;
   stbi_write_png_compression_level = QUAL;
   stbi_flip_vertically_on_write(FLIP);

   if (strncmp(input, "gen:", 4) == 0) {
      gen = input + 4; w = gw; h = gh;
      px = (strcmp(FMT, "hdr") == 0) ? (void *)gen_f32(gen, w, h, CMP)
                                     : (void *)gen_u8(gen, w, h, CMP);
   } else {
      if (strcmp(FMT, "hdr") == 0)
         px = stbi_loadf(input, &w, &h, NULL, incomp ? incomp : CMP);
      else
         px = stbi_load(input, &w, &h, NULL, incomp ? incomp : CMP);
   }
   if (!px) { fprintf(stderr, "cannot load/generate %s\n", input); return 2; }
   if (STRIDE <= 0) STRIDE = w * CMP;
   total_px = (double)w * (double)h;

   for (i = 0; i < repeats; ++i) {
      double t0, t1, per, single;
      long iters, k;

      if (!encode(px, w, h)) { fprintf(stderr, "encode failed\n"); return 1; }
      out_bytes = g_sink;

      t0 = now_s(); encode(px, w, h); t1 = now_s();
      single = t1 - t0; if (single <= 0) single = 1e-6;
      if (fixed_iters > 0) {
         iters = fixed_iters;
      } else {
         iters = (long)(budget / single);
         if (iters < 1) iters = 1;
         if (iters > 1000000) iters = 1000000;
      }

      t0 = now_s();
      for (k = 0; k < iters; ++k) {
         if (!encode(px, w, h)) { fprintf(stderr, "encode failed mid-bench\n"); return 1; }
      }
      t1 = now_s();
      per = (t1 - t0) / (double)iters;
      if (per < best_ns) { best_ns = per; best_iters = iters; }
   }

   printf("%s,%s,%d,%d,%d,%d,%lu,%ld,%.1f,%.4f,%.2f\n",
          input, FMT, CMP, QUAL, w, h, out_bytes, best_iters,
          best_ns * 1e9, best_ns * 1e9 / total_px, total_px / best_ns / 1e6);
   free(px);
   return 0;
}
