#pragma once
#if defined(__aarch64__) || defined(__arm__) || defined(_M_ARM64)
#include "sse2neon.h"
#else
#include <xmmintrin.h>
#include <emmintrin.h>
#endif
