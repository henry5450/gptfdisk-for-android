/*
 * Minimal libuuid-compatible header for Android (bionic).
 *
 * The NDK does not ship <uuid/uuid.h> and gptfdisk's guid.h includes it
 * unconditionally on non-Windows platforms.  This header provides the small
 * subset of the libuuid API that gptfdisk may use, backed by
 * android/uuid_compat.cc.
 */

#ifndef _UUID_UUID_H
#define _UUID_UUID_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned char uuid_t[16];

void uuid_generate(uuid_t out);
void uuid_generate_random(uuid_t out);
void uuid_generate_time(uuid_t out);
void uuid_clear(uuid_t uu);
void uuid_copy(uuid_t dst, const uuid_t src);
int uuid_compare(const uuid_t uu1, const uuid_t uu2);
int uuid_is_null(const uuid_t uu);
int uuid_parse(const char *in, uuid_t uu);
void uuid_unparse(const uuid_t uu, char *out);
void uuid_unparse_lower(const uuid_t uu, char *out);
void uuid_unparse_upper(const uuid_t uu, char *out);

#ifdef __cplusplus
}
#endif

#endif /* _UUID_UUID_H */
