/*
 * Minimal libuuid replacement for Android builds of gptfdisk.
 *
 * gptfdisk only needs random RFC 4122 version-4 UUIDs to identify disks and
 * partitions, so the full e2fsprogs libuuid is unnecessary.  Random bytes
 * come from /dev/urandom (with rand() as a last-resort fallback), and the
 * remaining functions are simple string/byte helpers for completeness.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <ctype.h>

#include <uuid/uuid.h>

static void FillRandom(uuid_t out) {
   int fd, got = 0;

   fd = open("/dev/urandom", O_RDONLY);
   if (fd >= 0) {
      got = (read(fd, out, 16) == 16);
      close(fd);
   } /* if */

   if (!got) {
      int i;
      for (i = 0; i < 16; i++)
         out[i] = (unsigned char) (rand() & 0xFF);
   } /* if */

   /* RFC 4122: version 4 (random), variant 1 (DCE) */
   out[6] = (unsigned char) ((out[6] & 0x0F) | 0x40);
   out[8] = (unsigned char) ((out[8] & 0x3F) | 0x80);
} /* FillRandom() */

void uuid_generate(uuid_t out) {
   FillRandom(out);
} /* uuid_generate() */

void uuid_generate_random(uuid_t out) {
   FillRandom(out);
} /* uuid_generate_random() */

void uuid_generate_time(uuid_t out) {
   /* No MAC address/clock sequence source on Android; a random UUID is
      perfectly acceptable for gptfdisk's purposes. */
   FillRandom(out);
} /* uuid_generate_time() */

void uuid_clear(uuid_t uu) {
   memset(uu, 0, 16);
} /* uuid_clear() */

void uuid_copy(uuid_t dst, const uuid_t src) {
   memcpy(dst, src, 16);
} /* uuid_copy() */

int uuid_compare(const uuid_t uu1, const uuid_t uu2) {
   return memcmp(uu1, uu2, 16);
} /* uuid_compare() */

int uuid_is_null(const uuid_t uu) {
   static const uuid_t nullUuid = {0};
   return (memcmp(uu, nullUuid, 16) == 0);
} /* uuid_is_null() */

static int HexVal(char c) {
   if (c >= '0' && c <= '9')
      return c - '0';
   c = (char) tolower((unsigned char) c);
   if (c >= 'a' && c <= 'f')
      return c - 'a' + 10;
   return -1;
} /* HexVal() */

int uuid_parse(const char *in, uuid_t uu) {
   int i, hi, lo, count = 0;

   if (strlen(in) != 36)
      return -1;
   for (i = 0; i < 36; i++) {
      if ((i == 8) || (i == 13) || (i == 18) || (i == 23)) {
         if (in[i] != '-')
            return -1;
      } else {
         hi = HexVal(in[i]);
         lo = HexVal(in[i + 1]);
         if ((hi < 0) || (lo < 0))
            return -1;
         uu[count++] = (unsigned char) ((hi << 4) | lo);
         i++; /* consumed two characters */
      } /* if/else */
   } /* for */
   return 0;
} /* uuid_parse() */

void uuid_unparse_lower(const uuid_t uu, char *out) {
   sprintf(out, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
           uu[0], uu[1], uu[2], uu[3], uu[4], uu[5], uu[6], uu[7],
           uu[8], uu[9], uu[10], uu[11], uu[12], uu[13], uu[14], uu[15]);
} /* uuid_unparse_lower() */

void uuid_unparse_upper(const uuid_t uu, char *out) {
   sprintf(out, "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
           uu[0], uu[1], uu[2], uu[3], uu[4], uu[5], uu[6], uu[7],
           uu[8], uu[9], uu[10], uu[11], uu[12], uu[13], uu[14], uu[15]);
} /* uuid_unparse_upper() */

void uuid_unparse(const uuid_t uu, char *out) {
   uuid_unparse_lower(uu, out);
} /* uuid_unparse() */
