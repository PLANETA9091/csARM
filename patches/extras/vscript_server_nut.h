// csARM: stub. vscript_server.cpp includes "vscript_server_nut.h" — Valve's
// precompiled Squirrel bootstrap header, absent from the public mirror.
// Provide an empty program; actual scripts load from the VPK/filesystem via
// VScriptRunScript at map start.
#ifndef CSARM_VSCRIPT_SERVER_NUT_H
#define CSARM_VSCRIPT_SERVER_NUT_H
static const char g_Script_vscript_server[] = "";
#endif
