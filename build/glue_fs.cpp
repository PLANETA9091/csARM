/* csARM — filesystem glue for the STANDALONE filesystem_init consumers.
 *
 * public/filesystem_init.cpp is compiled into appframework AND launcher AND
 * vgui; its FileSystem_LoadSearchPaths() calls
 * FileSystem_UpdateAddonSearchPaths(), whose only real implementation lives
 * in the ENGINE (engine/filesystem_engine.cpp).  The appframework/vgui
 * modules don't link the engine, so they get this no-op: addon/workshop
 * search paths don't exist on Android.
 * (Do not add this object to libengine — it defines the real one.)
 */
class IFileSystem;

void FileSystem_UpdateAddonSearchPaths(IFileSystem *pFileSystem) { (void)pFileSystem; }

/* vconfig.cpp implements GetVConfigRegistrySetting only under _WIN32 (Windows
 * registry); the matsys_controls build references it unconditionally.  There
 * is no registry on Android — report "setting absent". */
bool GetVConfigRegistrySetting(const char *pName, char *pReturn, int size)
{ (void)pName; (void)pReturn; (void)size; return false; }
