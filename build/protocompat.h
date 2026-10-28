#ifndef VALVE_PROTOCOMPAT_H
#define VALVE_PROTOCOMPAT_H

// csARM forced-include: byte-swap helpers.
// glibc and bionic both provide <byteswap.h> (bswap_16/32/64 macros +
// __bswap_* functions). Include it first, then only fill gaps with builtins.
#include <byteswap.h>

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
