#ifndef VALVE_PROTOCOMPAT_H
#define VALVE_PROTOCOMPAT_H
#ifndef bswap_16
#define bswap_16(x) __builtin_bswap16((unsigned short)(x))
#endif
#ifndef bswap_32
#define bswap_32(x) __builtin_bswap32((unsigned int)(x))
#endif
#ifndef bswap_64
#define bswap_64(x) __builtin_bswap64((unsigned long long)(x))
#endif
#ifndef __bswap_16
#define __bswap_16(x) __builtin_bswap16((unsigned short)(x))
#endif
#ifndef __bswap_32
#define __bswap_32(x) __builtin_bswap32((unsigned int)(x))
#endif
#ifndef __bswap_64
#define __bswap_64(x) __builtin_bswap64((unsigned long long)(x))
#endif
#endif
