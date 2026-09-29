/* write_dump - encode an image with stb_image_write and write the EXACT output
 * bytes to stdout, for bit-exact differential testing against the pristine
 * upstream oracle (and round-trip checking).
 *
 * The writer header under test is selected purely by include path:
 *   oracle:    cc -I upstream tools/write_dump.c
 *   candidate: cc -I src -I upstream tools/write_dump.c
 * `stb_image.h` is always taken from upstream/ (never modified by this fork).
 *
 * usage:
 *   write_dump <input> <format> <comp> <quality> [options]
 *
 *   <input>    path to a readable image file, OR "gen:<mode>"
 *              mode = grad | plasma | random | flat
 *   <format>   png | bmp | tga | hdr | jpg
 *   <comp>     output channels 1..4 (hdr: 1..4)
 *   <quality>  jpg quality (0..100); png compression level (e.g. 8)
 *
 * options:
 *   --dims WxH        dimensions for gen: inputs (default 256x256)
 *   --seed N          PRNG seed for gen:random (default 1)
 *   --stride N        explicit row stride in bytes (default w*comp)
 *   --incomp N        decode input as N channels (default: native)
 *   --force-filter N  stbi_write_force_png_filter (default -1)
 *   --rle 0|1         stbi_write_tga_with_rle
 *   --flip 0|1        stbi_flip_vertically_on_write
 *
 * stdout: raw encoded file bytes. exit 0 on success, 1 on writer failure,
 * 2 on usage/IO error.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include "gen.h"

static void out_cb(void *context, void *data, int size)
{
   (void)context;
   if (size > 0)
      fwrite(data, 1, (size_t)size, stdout);
}

int main(int argc, char **argv)
{
   const char *input, *format;
   int comp, quality;
   int genmode = 0;
   const char *gen = NULL;
   int gw = 256, gh = 256, seed = 1, stride = 0, incomp = 0;
   int force_filter = -1, rle = -1, flip = 0;
   int i, ret = 0;

   if (argc < 5) {
      fprintf(stderr, "usage: %s <input|gen:mode> <png|bmp|tga|hdr|jpg> <comp> <quality> [opts]\n", argv[0]);
      return 2;
   }
   input  = argv[1];
   format = argv[2];
   comp   = atoi(argv[3]);
   quality = atoi(argv[4]);
   if (comp < 1 || comp > 4) { fprintf(stderr, "bad comp\n"); return 2; }

   for (i = 5; i < argc; ++i) {
      if (strcmp(argv[i], "--dims") == 0 && i + 1 < argc) sscanf(argv[++i], "%dx%d", &gw, &gh);
      else if (strcmp(argv[i], "--seed") == 0 && i + 1 < argc) seed = atoi(argv[++i]);
      else if (strcmp(argv[i], "--stride") == 0 && i + 1 < argc) stride = atoi(argv[++i]);
      else if (strcmp(argv[i], "--incomp") == 0 && i + 1 < argc) incomp = atoi(argv[++i]);
      else if (strcmp(argv[i], "--force-filter") == 0 && i + 1 < argc) force_filter = atoi(argv[++i]);
      else if (strcmp(argv[i], "--rle") == 0 && i + 1 < argc) rle = atoi(argv[++i]);
      else if (strcmp(argv[i], "--flip") == 0 && i + 1 < argc) flip = atoi(argv[++i]);
      else { fprintf(stderr, "unknown option %s\n", argv[i]); return 2; }
   }
   g_seed = (uint32_t)seed;

   if (strncmp(input, "gen:", 4) == 0) {
      genmode = 1;
      gen = input + 4;
      if (gw <= 0 || gh <= 0) { fprintf(stderr, "bad dims\n"); return 2; }
   }

   if (force_filter >= 0) stbi_write_force_png_filter = force_filter;
   if (rle >= 0) stbi_write_tga_with_rle = rle;
   stbi_write_png_compression_level = quality;
   stbi_flip_vertically_on_write(flip);

   if (strcmp(format, "hdr") == 0) {
      float *pf = NULL;
      int w = gw, h = gh;
      if (genmode) {
         pf = gen_f32(gen, w, h, comp);
         if (!pf) return 2;
      } else {
         int sc;
         pf = stbi_loadf(input, &w, &h, &sc, incomp ? incomp : comp);
         if (!pf) { fprintf(stderr, "decode failed: %s\n", input); return 2; }
      }
      (void)stride;
      ret = stbi_write_hdr_to_func(out_cb, NULL, w, h, comp, pf);
      free(pf);
   } else {
      unsigned char *pu = NULL, *padded = NULL;
      const unsigned char *src;
      int w = gw, h = gh;
      if (genmode) {
         pu = gen_u8(gen, w, h, comp);
         if (!pu) return 2;
      } else {
         int sc;
         pu = stbi_load(input, &w, &h, &sc, incomp ? incomp : comp);
         if (!pu) { fprintf(stderr, "decode failed: %s\n", input); return 2; }
      }
      if (stride <= 0) stride = w * comp;
      src = pu;
      if (stride != w * comp) {
         /* Provide a genuinely padded buffer so a stride test never reads past
          * the source. Padding bytes are deterministic (0xA5). */
         int y, packed = w * comp;
         padded = (unsigned char *)malloc((size_t)stride * h);
         if (!padded) { free(pu); return 2; }
         for (y = 0; y < h; ++y) {
            memcpy(padded + (size_t)y * stride, pu + (size_t)y * packed, packed);
            memset(padded + (size_t)y * stride + packed, 0xA5, stride - packed);
         }
         src = padded;
      }

      if (strcmp(format, "png") == 0)
         ret = stbi_write_png_to_func(out_cb, NULL, w, h, comp, src, stride);
      else if (strcmp(format, "bmp") == 0)
         ret = stbi_write_bmp_to_func(out_cb, NULL, w, h, comp, src);
      else if (strcmp(format, "tga") == 0)
         ret = stbi_write_tga_to_func(out_cb, NULL, w, h, comp, src);
      else if (strcmp(format, "jpg") == 0)
         ret = stbi_write_jpg_to_func(out_cb, NULL, w, h, comp, src, quality);
      else {
         fprintf(stderr, "unknown format %s\n", format);
         free(padded); free(pu);
         return 2;
      }
      free(padded); free(pu);
   }

   if (fflush(stdout) != 0) return 2;
   return ret ? 0 : 1;
}
