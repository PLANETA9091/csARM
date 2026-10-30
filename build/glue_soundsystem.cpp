/* csARM — soundsystem glue for the Windows-only device backends.
 *
 * soundsystem.vpc compiles its wave device / ADPCM mixer / wave-source
 * factory unconditionally, but their implementations are Windows code that
 * does not port (engine's own audio path is used on Android; the SDL device
 * lives in soundsystem_lowlevel).  The factories below keep the exported
 * symbols of libsoundsystem.so resolvable and report "no device".
 */
class CWaveData;

#ifdef __cplusplus
extern "C" {
#endif

#ifdef __cplusplus
}
#endif

/* C++ factory functions (mangled) */
void *CreateADPCMMixer(CWaveData *pWaveData) { (void)pWaveData; return 0; }
void *Audio_CreateMemoryWave(const char *pWaveFilename) { (void)pWaveFilename; return 0; }
void *Audio_CreateWaveDevice(void) { return 0; }
