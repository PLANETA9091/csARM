/* csARM — materialsystem glue.
 *
 * g_pHardwareConfig (CHardwareConfig*, declared in
 * materialsystem/shaderapidx9/hardwareconfig.h) is owned by the shader API
 * (shaderapidx9), which is a D3D9->GL shim we do not port for the boot
 * milestone (it drags in togl + the whole shaderapi header web).  The
 * materialsystem binary references the pointer, so it must exist; the real
 * shader API will assign it once the render backend lands.
 */
class CHardwareConfig;

CHardwareConfig *g_pHardwareConfig = nullptr;
