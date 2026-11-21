// csARM round 80 — SHADER_DLL_INTERFACE_VERSION factory for libstdshader_dx9.so
//
// Upstream links shaderlib STATICALLY into the shader DLL (stdshader_dx9.vpc),
// so ShaderDLL.cpp's EXPOSE_INTERFACE_FN registry lives inside stdshader_dx9
// and answers CShaderSystem::LoadShaderDLL's SHADER_DLL_INTERFACE_VERSION
// ("ShaderDLL004") query.  This port links libshaderlib.so SHARED instead
// (link.sh round 55) and the shader classes' global ctors register into THAT
// lib's CShaderDLL singleton, so this DLL's factory must expose the SAME
// singleton — otherwise the version query returns NULL, the module is
// unloaded right after dlopen, the registered shaders never reach
// SetupShaderDictionary, every material falls back to the error material
// and the startup graphic crashes in CMeshDX8::SetVertexStreamState
// (run #232: 'UnlitGeneric' MISS counts=[136 -1 -1], SIGSEGV fault 0x1c).
#include "materialsystem/ishadersystem.h"
#include "tier1/interface.h"

EXPOSE_INTERFACE_FN( (InstantiateInterfaceFn)GetShaderDLLInternal, IShaderDLLInternal, SHADER_DLL_INTERFACE_VERSION );
