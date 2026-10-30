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

/* C++ factory functions (mangled).  WEAK on purpose: libsoundsystem_lowlevel
 * ships real (Linux/SDL) definitions of the same factories, and the auto-dep
 * relink adds -lsoundsystem_lowlevel to libsoundsystem.so — ld.lld refuses
 * strong-vs-strong duplicates, while weak-vs-strong links cleanly.  bionic
 * keeps the local (no-device) stub at runtime, which is what the Android
 * audio path expects (engine audio goes through SDL in lowlevel). */
__attribute__((weak)) void *CreateADPCMMixer(CWaveData *pWaveData) { (void)pWaveData; return 0; }
__attribute__((weak)) void *Audio_CreateMemoryWave(const char *pWaveFilename) { (void)pWaveFilename; return 0; }
__attribute__((weak)) void *Audio_CreateWaveDevice(void) { return 0; }
