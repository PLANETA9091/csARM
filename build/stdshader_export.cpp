// csARM round 80/81 — SHADER_DLL_INTERFACE_VERSION factory for libstdshader_dx9.so
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
// tier2.cpp (TIER2_CONN_O) defining ANOTHER g_pHardwareConfig.  Round 80
// fixed the version query by exposing the libshaderlib singleton; run #234
// then proved the second half of the split: DrawVertexLitGeneric_DX9_
// Internal crashed at 'mov (%r12)' reading g_pHardwareConfig@Base INSIDE
// libstdshader_dx9.so (fault 0x0) — the singleton Connect filled
// libshaderlib's copies, but the shader code reads its own, never-filled
// tier2 copy.
//
// So the exposed interface is a FORWARDING wrapper: Connect()/Disconnect()
// delegate to the libshaderlib singleton and additionally drive the LOCAL
// ConnectTier2Libraries/ConnectTier1Libraries (tier2/tier1 objects linked
// into this lib) so the shader TUs' globals get filled too.  Everything
// else forwards unchanged.
#include "materialsystem/ishadersystem.h"
#include "tier1/interface.h"
#include "tier2/tier2.h"

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
				// fill THIS module's copies of the tier1/tier2 globals
				// (g_pCVar, g_pHardwareConfig, g_pConfig, ...) that the
				// shader TUs compiled into libstdshader_dx9.so read
				ConnectTier1Libraries( &factory, 1 );
				ConnectTier2Libraries( &factory, 1 );
			}
			return bOK;
		}

		virtual void Disconnect( bool bIsMaterialSystem )
		{
			if ( !bIsMaterialSystem )
			{
				DisconnectTier2Libraries();
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
