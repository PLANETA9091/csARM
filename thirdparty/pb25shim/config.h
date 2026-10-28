/* csARM: hand-rolled config for protobuf 2.5.0 on Android (bionic aarch64).
 * The upstream tree expects autotools to generate this file; we ship a fixed
 * one because the bionic feature set is stable and known.
 * zlib is NOT available on the Android link line (no libz headers shipped in
 * this build) -> HAVE_ZLIB stays undefined and gzip_stream.cc is excluded. */
#ifndef CSARM_PB25_CONFIG_H
#define CSARM_PB25_CONFIG_H

#include <stddef.h>  /* for size_t */

/* bionic exposes pthreads; enables Mutex/Thread support */
#define HAVE_PTHREAD 1

/* bionic has hash_map/hash_set as std::hash_map etc. under libc++ we use
 * std::(unordered_)map via the standard path, so leave HAVE_HASH_MAP and
 * HAVE_HASH_SET undefined -> code falls back to std::map/std::set. */

/* libc++ has long long */
#define HAVE_LONG_LONG 1

#endif /* CSARM_PB25_CONFIG_H */
