/* Isolated kernel microbenchmarks for stb_image_write's deflate path.
 *
 * usage: kernbench [budget_s] [repeats]
 * output (CSV): kernel,metric,value,unit,iters
 *
 * Build with and without -DSTBIW_NO_SIMD to compare the SSE2 match kernel
 * against the scalar fallback (harness/kernbench.sh does both).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

static double now_s(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static volatile unsigned g_sink;

static double bench_countm(int L, double budget, int repeats)
{
   static unsigned char A[2048], B[2048];
   int i, r;
   long iters, k;
   double best = 1e300;
   for (i = 0; i < 2048; ++i) A[i] = (unsigned char)(i * 7 + 1);
   memcpy(B, A, sizeof(B));
   B[L] ^= 0x80;               /* first mismatch at byte L */
   {
      double t0 = now_s();
      for (k = 0; k < 1000; ++k) g_sink += stbiw__zlib_countm(A, B, 2048);
      iters = (long)(budget / ((now_s() - t0) / 1000.0));
   }
   if (iters < 1) iters = 1;
   for (r = 0; r < repeats; ++r) {
      double t0 = now_s(), per;
      for (k = 0; k < iters; ++k) g_sink += stbiw__zlib_countm(A, B, 2048);
      per = (now_s() - t0) / (double)iters;
      if (per < best) best = per;
   }
   return best;
}

static unsigned char *make_deflate_input(int n, int *out_len)
{
   unsigned char *p = (unsigned char *)malloc((size_t)n);
   int i;
   if (!p) return NULL;
   for (i = 0; i < n; ++i) {
      /* mixture of runs and slowly varying data: compressible but not trivial */
      int block = i >> 5;
      p[i] = (unsigned char)((block & 1) ? 0x40 : ((i * 3) & 0x3f));
   }
   *out_len = n;
   return p;
}

static double bench_deflate(unsigned char *in, int n, double budget, int repeats,
                            unsigned long *out_bytes, long *out_iters)
{
   long iters = 1, k;
   double best = 1e300, single;
   int zlen = 0;
   unsigned char *z;
   double t0 = now_s();
   z = stbi_zlib_compress(in, n, &zlen, 8);
   single = now_s() - t0;
   if (!z) return -1.0;
   *out_bytes = (unsigned long)zlen;
   free(z);
   if (single <= 0) single = 1e-6;
   iters = (long)(budget / single);
   if (iters < 1) iters = 1;
   if (iters > 100000) iters = 100000;
   for (k = 0; k < repeats; ++k) {
      double per;
      long m;
      t0 = now_s();
      for (m = 0; m < iters; ++m) {
         z = stbi_zlib_compress(in, n, &zlen, 8);
         if (!z) return -1.0;
         free(z);
      }
      per = (now_s() - t0) / (double)iters;
      if (per < best) best = per;
   }
   *out_iters = iters;
   return best;
}

int main(int argc, char **argv)
{
   double budget = 0.1;
   int repeats = 7;
   int lens[] = { 3, 8, 16, 64, 258 };
   unsigned char *in;
   int inlen = 0;
   unsigned long zbytes = 0;
   double ns;
   int i;

   if (argc > 1) budget = atof(argv[1]);
   if (argc > 2) repeats = atoi(argv[2]);

   printf("kernel,metric,value,unit,iters\n");
   for (i = 0; i < (int)(sizeof(lens)/sizeof(lens[0])); ++i) {
      long iters;
      ns = bench_countm(lens[i], budget, repeats);
      iters = 0;
      printf("countm_L%d,ns_per_call,%.3f,ns,%ld\n", lens[i], ns * 1e9, iters);
   }

   in = make_deflate_input(1 << 18, &inlen);  /* 256 KiB */
   if (in) {
      long diters = 0;
      ns = bench_deflate(in, inlen, budget, repeats, &zbytes, &diters);
      printf("deflate,ns_per_byte,%.4f,ns,%ld\n", ns * 1e9 / inlen, diters);
      printf("deflate,compressed_bytes,%lu,bytes,%ld\n", zbytes, diters);
      free(in);
   }
   return 0;
}
