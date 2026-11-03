/* csARM — engine-side platform stubs for closed-source middleware:
 *
 *   - libjpeg (JPEG screenshot compression): no libjpeg source in
 *     cstrike15_src and Valve ships only prebuilt binaries; the engine's
 *     CL_TakeJpeg path degrades gracefully (screenshot fails, game runs).
 *   - Phonon binaural spatializer (ipl* API): Valve ships libphonon3d as a
 *     prebuilt x86 binary, no source, no ARM build; the sound code calls it
 *     conditionally behind the phonon mixer path.
 *   - DirectSound voice capture (Windows-only backend stubbed by Valve's own
 *     VPC on other platforms).
 */
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --- libjpeg subset used by the engine's screenshot path ------------------ */
struct jpeg_error_mgr_stub { int dummy; };
static struct jpeg_error_mgr_stub s_jpeg_err;

void *jpeg_std_error(void *errmgr) { return errmgr ? errmgr : &s_jpeg_err; }
void jpeg_CreateCompress(void *cinfo, int version, size_t structsize)
{ (void)cinfo; (void)version; (void)structsize; }
void jpeg_start_compress(void *cinfo, int write_all_tables) { (void)cinfo; (void)write_all_tables; }
void jpeg_finish_compress(void *cinfo) { (void)cinfo; }
void jpeg_destroy_compress(void *cinfo) { (void)cinfo; }
void jpeg_set_defaults(void *cinfo) { (void)cinfo; }
void jpeg_set_quality(void *cinfo, int quality, int force_baseline)
{ (void)cinfo; (void)quality; (void)force_baseline; }
void jpeg_write_scanlines(void *cinfo, unsigned char **scanlines, int num)
{ (void)cinfo; (void)scanlines; (void)num; }

/* --- Phonon binaural spatializer (ipl* API) ------------------------------- *
 * Valve ships libphonon3d as a prebuilt binary (no source, no ARM build).
 * The 2019 partner tree carries the Steam Audio 2.x SDK header
 * (public/phonon/phonon.h) and calls the full API from the engine audio
 * path (SND_Init occlusion in snd_dma.cpp, per-channel HRTF/occlusion in
 * snd_wave_data.cpp).  Every caller checks the returned status and
 * degrades cleanly: create-failures log a DevMsg and disable the feature
 * (snd_hwcompat / snd_occlusion flip off, the null-device path stays).
 * The stubs below therefore report IPL_STATUS_FAILURE from every factory
 * and no-op the apply/destroy/set family — spatial audio is simply off. */
#include <phonon/phonon.h>

IPLerror iplCreateScene(IPLContext context, IPLhandle computeDevice,
                        IPLSimulationSettings simulationSettings,
                        IPLint32 numMaterials, IPLhandle* scene)
{ (void)context; (void)computeDevice; (void)simulationSettings; (void)numMaterials;
  (void)scene; return IPL_STATUS_FAILURE; }

IPLvoid iplSetSceneMaterial(IPLhandle scene, IPLint32 materialIndex, IPLMaterial material)
{ (void)scene; (void)materialIndex; (void)material; }

IPLvoid iplFinalizeScene(IPLhandle scene, IPLFinalizeSceneProgressCallback progressCallback)
{ (void)scene; (void)progressCallback; }

IPLerror iplCreateEnvironment(IPLContext context, IPLhandle computeDevice,
                              IPLSimulationSettings simulationSettings,
                              IPLhandle scene, IPLhandle probeManager, IPLhandle* environment)
{ (void)context; (void)computeDevice; (void)simulationSettings; (void)scene;
  (void)probeManager; (void)environment; return IPL_STATUS_FAILURE; }

IPLerror iplCreateEnvironmentalRenderer(IPLContext context, IPLhandle environment,
                                        IPLRenderingSettings renderingSettings,
                                        IPLAudioFormat outputFormat,
                                        IPLSimulationThreadCreateCallback threadCreateCallback,
                                        IPLSimulationThreadDestroyCallback threadDestroyCallback,
                                        IPLhandle* renderer)
{ (void)context; (void)environment; (void)renderingSettings; (void)outputFormat;
  (void)threadCreateCallback; (void)threadDestroyCallback; (void)renderer;
  return IPL_STATUS_FAILURE; }

IPLerror iplCreateBinauralRenderer(IPLContext context, IPLRenderingSettings renderingSettings,
                                   IPLHrtfParams params, IPLhandle* renderer)
{ (void)context; (void)renderingSettings; (void)params; (void)renderer;
  return IPL_STATUS_FAILURE; }

IPLerror iplCreateBinauralEffect(IPLhandle renderer, IPLAudioFormat inputFormat,
                                 IPLAudioFormat outputFormat, IPLhandle* effect)
{ (void)renderer; (void)inputFormat; (void)outputFormat; (void)effect;
  return IPL_STATUS_FAILURE; }

IPLvoid iplDestroyBinauralEffect(IPLhandle* effect) { (void)effect; }

IPLvoid iplApplyBinauralEffect(IPLhandle effect, IPLAudioBuffer inputAudio,
                               IPLVector3 direction, IPLHrtfInterpolation interpolation,
                               IPLAudioBuffer outputAudio)
{ (void)effect; (void)inputAudio; (void)direction; (void)interpolation; (void)outputAudio; }

IPLvoid iplApplyBinauralEffectWithParameters(IPLhandle effect, IPLAudioBuffer inputAudio,
                                             IPLVector3 direction,
                                             IPLHrtfInterpolation interpolation,
                                             IPLAudioBuffer outputAudio,
                                             IPLfloat32* leftDelay, IPLfloat32* rightDelay)
{ (void)effect; (void)inputAudio; (void)direction; (void)interpolation; (void)outputAudio;
  (void)leftDelay; (void)rightDelay; }

IPLerror iplCreateDirectSoundEffect(IPLhandle renderer, IPLAudioFormat inputFormat,
                                    IPLAudioFormat outputFormat, IPLhandle* effect)
{ (void)renderer; (void)inputFormat; (void)outputFormat; (void)effect;
  return IPL_STATUS_FAILURE; }

IPLvoid iplDestroyDirectSoundEffect(IPLhandle* effect) { (void)effect; }

IPLvoid iplApplyDirectSoundEffect(IPLhandle effect, IPLAudioBuffer inputAudio,
                                  IPLDirectSoundPath directSoundPath,
                                  IPLDirectSoundEffectOptions options,
                                  IPLAudioBuffer outputAudio)
{ (void)effect; (void)inputAudio; (void)directSoundPath; (void)options; (void)outputAudio; }

#ifdef __cplusplus
}
#endif

/* --- DirectSound voice capture (Windows-only; never used on Android) ----- */
void *CreateVoiceRecord_DSound(int rate) { (void)rate; return 0; }

/* --- Windows audio-mixer controls (voice_mixer_controls.cpp is MIXERCONTROL-
 * based Windows code; the engine references the trio below unconditionally,
 * callers null-check g_pMixerControls before use) ------------------------- */
class CMixerControls;
CMixerControls *g_pMixerControls = nullptr;
void InitMixerControls(void) {}
void ShutdownMixerControls(void) {}

/* [port] g_bReplayLoadedTools: the 2019 tree defines it itself in
 * engine/toolframework.cpp - no glue definition needed. */

/* --- EmitJSONString (C++ linkage) ----------------------------------------- *
 * game/client/cstrike15/uicomponents/uicomponent_common.cpp declares
 * "extern void EmitJSONString( CUtlBuffer&, const char* )" ("Using this from
 * webapi_response to reuse some code") but webapi_response.cpp is not part
 * of the partner depot — the definition is missing from the 2019 tree
 * entirely (run #146: libclient dlopen failed on
 * _Z14EmitJSONStringR10CUtlBufferPKc).  Re-implement the obvious JSON
 * string escaper on CUtlBuffer. */
#include "tier1/utlbuffer.h"

void EmitJSONString( CUtlBuffer &outputBuffer, const char *pchValue )
{
	if ( !pchValue )
	{
		outputBuffer.Put( "null", 4 );
		return;
	}
	outputBuffer.PutChar( '"' );
	for ( const char *p = pchValue; *p; ++p )
	{
		switch ( *p )
		{
			case '"':	outputBuffer.Put( "\\\"", 2 ); break;
			case '\\':	outputBuffer.Put( "\\\\", 2 ); break;
			case '\n':	outputBuffer.Put( "\\n", 2 ); break;
			case '\r':	outputBuffer.Put( "\\r", 2 ); break;
			case '\t':	outputBuffer.Put( "\\t", 2 ); break;
			default:
				if ( (unsigned char)*p < 0x20 )
				{
					char tmp[8];
					V_snprintf( tmp, sizeof( tmp ), "\\u%04x", (unsigned char)*p );
					outputBuffer.Put( tmp, 6 );
				}
				else
				{
					outputBuffer.PutChar( *p );
				}
		}
	}
	outputBuffer.PutChar( '"' );
}
