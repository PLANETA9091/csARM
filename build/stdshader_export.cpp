// csARM round 80/81/82 — SHADER_DLL_INTERFACE_VERSION factory for libstdshader_dx9.so
//
// Upstream links shaderlib STATICALLY into the shader DLL (stdshader_dx9.vpc),
// so ShaderDLL.cpp's EXPOSE_INTERFACE_FN registry lives inside stdshader_dx9
// and answers CShaderSystem::LoadShaderDLL's SHADER_DLL_INTERFACE_VERSION
// ("ShaderDLL004") query, AND CShaderDLL::Connect's direct assignments fill
// the g_pHardwareConfig/g_pConfig/g_pSLShaderSystem copies the shaders read
// (they are in the same static link, defined by ShaderDLL.cpp + tier2.cpp).
//
// This port splits that static link: libshaderlib.so holds ShaderDLL.cpp and
// libstdshader_dx9.so links it SHARED, while the shader TUs carry their own
// copies of those globals (TIER2_CONN_O / shader TU data).  Round 80 fixed
// the version query by exposing the libshaderlib singleton; run #234 proved
// the second half of the split: DrawVertexLitGeneric_DX9_Internal crashed at
// 'mov (%r12)' reading g_pHardwareConfig@Base INSIDE libstdshader_dx9.so
// (fault 0x0) — the singleton Connect filled libshaderlib's copies, but the
// shader code reads its own, never-filled copy.  Round 81 tried
// ConnectTier2Libraries — but in the 2019 tree that function only registers
// the precache/resource systems and does NOT touch these globals; the real
// fill is the three direct factory() assignments in ShaderDLL.cpp's Connect.
//
// So the exposed interface is a FORWARDING wrapper: Connect()/Disconnect()
// delegate to the libshaderlib singleton and additionally fill THIS module's
// copies of the tier globals exactly like ShaderDLL.cpp::Connect does, plus
// ConnectTier1Libraries for the local tier1 globals (g_pCVar).  Everything
// else forwards unchanged.
#include "materialsystem/ishadersystem.h"
#include "materialsystem/imaterialsystemhardwareconfig.h"
#include "materialsystem/materialsystem_config.h"
#include "tier1/interface.h"
#include "tier1/tier1.h"

// These are defined per-module (ShaderDLL.cpp in libshaderlib, tier2.cpp-adjacent
// copies in the shader DLL); the externs below bind to THIS module's copies.
extern IMaterialSystemHardwareConfig *g_pHardwareConfig;
extern const MaterialSystem_Config_t *g_pConfig;
extern IShaderSystem *g_pSLShaderSystem;

namespace StdShaderExport
{
	class CShaderDLLForward : public IShaderDLLInternal
	{
	public:
		explicit CShaderDLLForward( IShaderDLLInternal *pInner ) : m_pInner( pInner ) {}

		virtual bool Connect( CreateInterfaceFn factory, bool bIsMaterialSystem )
		{
			bool bOK = m_pInner->Connect( factory, bIsMaterialSystem );
			if ( !bIsMaterialSystem )
			{
				// fill THIS module's copies of the tier globals that the
				// shader TUs compiled into libstdshader_dx9.so read —
				// the mirror of ShaderDLL.cpp::Connect's assignments
				g_pHardwareConfig = (IMaterialSystemHardwareConfig *)factory( MATERIALSYSTEM_HARDWARECONFIG_INTERFACE_VERSION, NULL );
				g_pConfig = (const MaterialSystem_Config_t *)factory( MATERIALSYSTEM_CONFIG_VERSION, NULL );
				g_pSLShaderSystem = (IShaderSystem *)factory( SHADERSYSTEM_INTERFACE_VERSION, NULL );
				// local tier1 globals (g_pCVar) for the shader cvars
				ConnectTier1Libraries( &factory, 1 );
			}
			return bOK;
		}

		virtual void Disconnect( bool bIsMaterialSystem )
		{
			if ( !bIsMaterialSystem )
			{
				g_pHardwareConfig = NULL;
				g_pConfig = NULL;
				g_pSLShaderSystem = NULL;
				DisconnectTier1Libraries();
			}
			m_pInner->Disconnect( bIsMaterialSystem );
		}

		virtual int ShaderCount() const { return m_pInner->ShaderCount(); }
		virtual IShader *GetShader( int nShader ) { return m_pInner->GetShader( nShader ); }
		virtual int ShaderComboSemanticsCount() const { return m_pInner->ShaderComboSemanticsCount(); }
		virtual const ShaderComboSemantics_t *GetComboSemantics( int n ) { return m_pInner->GetComboSemantics( n ); }

	private:
		IShaderDLLInternal *m_pInner;
	};

	static void *MakeShaderDLLForward()
	{
		static CShaderDLLForward s_Forward( GetShaderDLLInternal() );
		return &s_Forward;
	}
}

EXPOSE_INTERFACE_FN( (InstantiateInterfaceFn)StdShaderExport::MakeShaderDLLForward, IShaderDLLInternal, SHADER_DLL_INTERFACE_VERSION );
