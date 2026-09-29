/* Translation unit for the prebuilt drop-in static library. The public API and
 * ABI are exactly upstream stb_image_write.h; this file only instantiates the
 * implementation. Consumers include src/stb_image_write.h WITHOUT
 * STB_IMAGE_WRITE_IMPLEMENTATION and link this library. */
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
