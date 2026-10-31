// csARM — BSP lump globals for raytrace/trace3.cpp (tool-only code paths:
// RayTracingEnvironment's "load faces from BSP file" helpers reference the
// bspfile working arrays declared in utils/common/bsplib.h).  At engine
// boot nothing calls these paths, but the references must resolve for
// dlopen.  Provide placeholder storage with the SAME LINKAGE the .so
// references use (unmangled C symbols — verified against the reach-gate
// report); element sizes are baked into the referencing TU, so any sized
// buffer keeps the relocations happy.
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// alignas(16): the real dvertex_t/dedge_t/dface_t carry float/simd members.
// Element sizes are baked into the referencing TU, so one-element buffers
// keep every relocation satisfied without wasting space.
__attribute__((aligned(16))) unsigned char dvertexes[1];
__attribute__((aligned(16))) unsigned char dedges[1];
__attribute__((aligned(16))) unsigned char dorigfaces[1];
__attribute__((aligned(16))) unsigned char texinfo[1];
int numfaces = 0;
__attribute__((aligned(16))) int dsurfedges[1] = { 0 };

#ifdef __cplusplus
}
#endif
