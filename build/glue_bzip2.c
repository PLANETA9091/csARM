/* csARM — V_isspace shim for utils/bzip2 (bzip2.c is C and cannot inline
 * the C++ inline V_isspace from public/tier1/strtools.h). */
#include <ctype.h>

#ifdef __cplusplus
extern "C" {
#endif

int V_isspace(int c) { return isspace(c) ? 1 : 0; }

#ifdef __cplusplus
}
#endif
