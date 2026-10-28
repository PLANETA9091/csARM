#ifndef VALVE_PROTOCOMPAT_H
#define VALVE_PROTOCOMPAT_H

// csARM forced-include: byte-swap helpers, glibc/bionic-safe.
//
// IMPORTANT: do NOT #include <byteswap.h> here. The project -I paths put
// c15/public/tier1 first, so <byteswap.h> would resolve to Valve's header and
// drag the whole tier0/tier1 include chain into plain .c files (bzip2 etc.),
// where it does not compile. Instead we only FILL GAPS if the system macros
// are not present: both glibc and bionic define bswap_16/32/64 when their own
// <byteswap.h> is included, and nothing in the tree uses the glibc-only
// __bswap_* names (crypto++ misc.h is patched to use builtins).

#ifndef bswap_16
#define bswap_16(x) __builtin_bswap16((unsigned short)(x))
#endif
#ifndef bswap_32
#define bswap_32(x) __builtin_bswap32((unsigned int)(x))
#endif
#ifndef bswap_64
#define bswap_64(x) __builtin_bswap64((unsigned long long)(x))
#endif

#endif
