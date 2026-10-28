// csARM: stub. cstrike15_src references "spawn_helper_nut.h" (vscript spawn
// helpers) but the file is absent from the public mirror. point_template.cpp
// runs g_Script_spawn_helper through the VM, so provide an empty program:
// mapspawn/vscript logic still loads from .nut files via VScriptRunScript.
#ifndef CSARM_SPAWN_HELPER_NUT_H
#define CSARM_SPAWN_HELPER_NUT_H
static const char g_Script_spawn_helper[] = "";
#endif
