// csARM: compile-time-only stub of KHR/khrplatform.h (Android NDK sysroot has
// the real one; this is for host-side syntax validation builds).
#ifndef __khrplatform_h_
#define __khrplatform_h_
#include <stdint.h>
typedef int32_t khronos_int32_t;
typedef uint16_t khronos_uint16_t;
typedef uint32_t khronos_uint32_t;
typedef int64_t khronos_int64_t;
typedef uint64_t khronos_uint64_t;
typedef float khronos_float_t;
typedef khronos_uint64_t khronos_utimes_nanoseconds_t;
typedef khronos_int64_t khronos_timespec_nanoseconds_t;
typedef intptr_t khronos_intptr_t;
typedef uintptr_t khronos_uintptr_t;
typedef uintptr_t khronos_size_t;
typedef ptrdiff_t khronos_ssize_t;
typedef unsigned long long khronos_usize_t;
#define KHRONOS_SUPPORT_INT64 1
#define KHRONOS_SUPPORT_FLOAT 1
#define KHRONOS_APIENTRY
#define KHRONOS_APIATTRIBUTES
#endif
