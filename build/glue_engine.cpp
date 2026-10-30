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

/* --- Phonon binaural spatializer (ipl* = Steam Audio 2015 era) ------------ */
void *iplCreate3DContext(void *renderPath, void *hrtf, void *simulationSettings)
{ (void)renderPath; (void)hrtf; (void)simulationSettings; return 0; }
void *iplCreateBinauralEffect(void *context, void *audioCfg, void *effectCfg)
{ (void)context; (void)audioCfg; (void)effectCfg; return 0; }
void iplDestroyBinauralEffect(void *effect) { (void)effect; }
void iplApplyBinauralEffect(void *effect, void *in, void *out, int directionIndex,
                            float spatialBlend, float dualBandHiFreqAmt)
{ (void)effect; (void)in; (void)out; (void)directionIndex; (void)spatialBlend; (void)dualBandHiFreqAmt; }

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
