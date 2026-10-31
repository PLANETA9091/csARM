#!/usr/bin/env python3
"""csARM — extend patches/extras/csarm_boot.diff with launcher/appframework/
engine boot-path probes + the __ANDROID__ appSystems table adjustments.

Usage: gen_boot_diff.py <tmpdir-with-fetched-sources> <repo-root>
Reads:  $TMP/appsys.cpp       (c15 appframework/AppSystemGroup.cpp)
        $TMP/launcher.cpp     (c15 launcher/launcher.cpp)
        $TMP/sys_dll2.cpp     (c15 engine/sys_dll2.cpp)
        $TMP/sdlmgr.cpp       (c15 appframework/sdlmgr.cpp)
        $TMP/threadtools.inl  (c15 public/tier0/threadtools.inl)
        $TMP/jobthread.cpp    (c15 vstdlib/jobthread.cpp)
        $TMP/descriptor.cc    (c15 thirdparty/protobuf-2.5.0 .../descriptor.cc)
        $TMP/message.cc       (c15 thirdparty/protobuf-2.5.0 .../message.cc)
Writes: $REPO/patches/extras/csarm_boot.diff  (sys_engine hunk is preserved)

Valve sources are TAB-indented — every anchor below uses explicit \t escapes.
"""
import difflib
import sys
import os

tmp, repo = sys.argv[1], sys.argv[2]

CSARM_LOG_H = '''// csARM - direct logcat logging from patched Valve sources.
// printf/stderr are redirected to logcat by libmain, but the app-framework
// failure paths run before any spew listener is installed and the process
// can exit(0) without flushing - __android_log_print cannot be missed.
#ifndef CSARM_LOG_H
#define CSARM_LOG_H

#ifdef __ANDROID__
#include <android/log.h>
#define CSARM_LOGI(...) __android_log_print(ANDROID_LOG_INFO,  "CSARM_LNCH", __VA_ARGS__)
#define CSARM_LOGW(...) __android_log_print(ANDROID_LOG_WARN,  "CSARM_LNCH", __VA_ARGS__)
#else
#define CSARM_LOGI(...) ((void)0)
#define CSARM_LOGW(...) ((void)0)
#endif

#endif // CSARM_LOG_H
'''

def die(msg):
    print('FATAL: ' + msg)
    sys.exit(1)

def unified(a_text, b_text, apath):
    diff = difflib.unified_diff(
        a_text.splitlines(keepends=True), b_text.splitlines(keepends=True),
        fromfile='a/' + apath, tofile='b/' + apath, n=3)
    lines = list(diff)
    if not lines:
        die(f'{apath}: no diff produced')
    # difflib emits: '--- a/..', '+++ b/..', '@@ ..' — prepend only the
    # git-style header; overwriting lines[2] would eat the first @@ hunk
    return f'diff --git a/{apath} b/{apath}\n' + ''.join(lines)

def apply(text, name, pairs):
    for old, new in pairs:
        n = text.count(old)
        if n != 1:
            die(f'{name}: anchor found {n}x (want 1):\n{old!r}')
        text = text.replace(old, new)
    return text

T = '\t'
out = []

# ---------------------------------------------------------------- AppSystemGroup.cpp
text = open(os.path.join(tmp, 'appsys.cpp')).read()
pairs = []
pairs.append((
    '#include "filesystem_init.h"\n#include <algorithm>',
    '#include "filesystem_init.h"\n#include "common/csarm_log.h"\n#include <algorithm>'))

pairs.append((
    T + 'while ( pSystemList->m_pModuleName[0] )\n'
    + T + '{\n'
    + T + '\tAppModule_t module = LoadModule( pSystemList->m_pModuleName );\n'
    + T + '\tIAppSystem *pSystem = AddSystem( module, pSystemList->m_pInterfaceName );\n'
    + T + '\tif ( !pSystem )\n'
    + T + '\t{\n'
    + T + '\t\tWarning( "Unable to load interface %s from %s, requested from EXE.\\n", pSystemList->m_pInterfaceName, pSystemList->m_pModuleName );',
    T + 'while ( pSystemList->m_pModuleName[0] )\n'
    + T + '{\n'
    + T + '\tCSARM_LOGI( "AddSystem %s <- %s", pSystemList->m_pInterfaceName, pSystemList->m_pModuleName );\n'
    + T + '\tAppModule_t module = LoadModule( pSystemList->m_pModuleName );\n'
    + T + '\tIAppSystem *pSystem = AddSystem( module, pSystemList->m_pInterfaceName );\n'
    + T + '\tif ( !pSystem )\n'
    + T + '\t{\n'
    + T + '\t\tCSARM_LOGW( "FAILED AddSystem %s <- %s", pSystemList->m_pInterfaceName, pSystemList->m_pModuleName );\n'
    + T + '\t\tWarning( "Unable to load interface %s from %s, requested from EXE.\\n", pSystemList->m_pInterfaceName, pSystemList->m_pModuleName );'))

for stage, call in [
    ('CREATION', 'if ( !Create() )'),
    ('DEPENDENCIES', 'if ( !LoadDependentSystems() )'),
    ('CONNECTION', 'if ( !ConnectSystems() )'),
    ('PREINITIALIZATION', 'if ( !PreInit() )'),
    ('POSTINITIALIZATION', 'if ( !PostInit() )'),
]:
    old = (T + f'm_nCurrentStage = {stage};\n'
           + T + call + '\n'
           + T + '\treturn -1;\n')
    new = (T + f'm_nCurrentStage = {stage};\n'
           + T + f'CSARM_LOGI( "stage {stage}" );\n'
           + T + call + '\n'
           + T + '{\n'
           + T + '\tCSARM_LOGW( "FAILED at stage ' + stage + '" );\n'
           + T + '\treturn -1;\n'
           + T + '}\n')
    pairs.append((old, new))

pairs.append((
    T + 'm_nCurrentStage = INITIALIZATION;\n'
    + T + 'int nRetVal = InitSystems();\n'
    + T + 'if ( nRetVal != INIT_OK )\n'
    + T + '\treturn -1;\n',
    T + 'm_nCurrentStage = INITIALIZATION;\n'
    + T + 'CSARM_LOGI( "stage INITIALIZATION" );\n'
    + T + 'int nRetVal = InitSystems();\n'
    + T + 'if ( nRetVal != INIT_OK )\n'
    + T + '{\n'
    + T + '\tCSARM_LOGW( "FAILED at stage INITIALIZATION" );\n'
    + T + '\treturn -1;\n'
    + T + '}\n'))

# FindSystem diagnostics: log state whenever the dict+QueryInterface lookups
# both miss (the parent-chain lookup follows).  Run 41145122796: materialsystem
# Connect() saw a NULL filesystem through this path.
pairs.append((
    T + T + 'void *pInterface = m_Systems[i]->QueryInterface( pSystemName );\n'
    + T + T + 'if (pInterface)\n'
    + T + T + T + 'return pInterface;\n'
    + T + '}\n',
    T + T + 'void *pInterface = m_Systems[i]->QueryInterface( pSystemName );\n'
    + T + T + 'if (pInterface)\n'
    + T + T + T + 'return pInterface;\n'
    + T + '}\n'
    + T + 'CSARM_LOGI( "FindSystem MISS %s: systems=%d parent=%p", pSystemName, (int)m_Systems.Count(), (void*)m_pParentAppSystem );\n'))

orig = text
text = apply(text, 'appsys.cpp', pairs)
out.append(unified(orig, text, 'appframework/AppSystemGroup.cpp'))

# ---------------------------------------------------------------- launcher.cpp
text = open(os.path.join(tmp, 'launcher.cpp')).read()
pairs = []
pairs.append((
    '#include "tier0/icommandline.h"\n',
    '#include "tier0/icommandline.h"\n#include "common/csarm_log.h"\n'))

pairs.append((
    T + '\t' + '{ LAUNCHER_APPSYSTEM( "vphysics" ),\t\t\t\tVPHYSICS_INTERFACE_VERSION },\n',
    T + '\t' + '#ifdef __ANDROID__\n'
    + T + '\t' + '// csARM: the cstrike15 source mirror does not ship the vphysics\n'
    + T + '\t' + '// library; physics is map-load-time functionality, boot does not\n'
    + T + '\t' + '// need it.  Restore once vphysics is ported.\n'
    + T + '\t' + '#else\n'
    + T + '\t' + '{ LAUNCHER_APPSYSTEM( "vphysics" ),\t\t\t\tVPHYSICS_INTERFACE_VERSION },\n'
    + T + '\t' + '#endif\n'))

pairs.append((
    T + '\t' + '{ LAUNCHER_APPSYSTEM( "vscript" ),\t\t\t\tVSCRIPT_INTERFACE_VERSION },\n',
    T + '\t' + '#ifdef __ANDROID__\n'
    + T + '\t' + '// csARM: vscript (Squirrel/Lua VM) is not ported yet - the boot\n'
    + T + '\t' + '// path does not execute game scripts.  Restore with the port.\n'
    + T + '\t' + '#else\n'
    + T + '\t' + '{ LAUNCHER_APPSYSTEM( "vscript" ),\t\t\t\tVSCRIPT_INTERFACE_VERSION },\n'
    + T + '\t' + '#endif\n'))

pairs.append((
    T + '\t' + '{ LAUNCHER_APPSYSTEM( "vgui2" ),\t\t\t\tVGUI_IVGUI_INTERFACE_VERSION },\n',
    T + '\t' + '#ifdef __ANDROID__\n'
    + T + '\t' + '{ LAUNCHER_APPSYSTEM( "vgui" ),\t\t\t\tVGUI_IVGUI_INTERFACE_VERSION }, // csARM: our vgui2 build is libvgui.so\n'
    + T + '\t' + '#else\n'
    + T + '\t' + '{ LAUNCHER_APPSYSTEM( "vgui2" ),\t\t\t\tVGUI_IVGUI_INTERFACE_VERSION },\n'
    + T + '\t' + '#endif\n'))

pairs.append((
    T + 'COM_TimestampedLog( "CSourceAppSystemGroup::Create()" );\n',
    T + 'COM_TimestampedLog( "CSourceAppSystemGroup::Create()" );\n'
    + T + 'CSARM_LOGI( "CSourceAppSystemGroup::Create enter" );\n'))

pairs.append((
    T + 'IFileSystem *pFileSystem = (IFileSystem*)FindSystem( FILESYSTEM_INTERFACE_VERSION );\n'
    + T + 'pFileSystem->InstallDirtyDiskReportFunc( ReportDirtyDiskNoMaterialSystem );\n',
    T + 'IFileSystem *pFileSystem = (IFileSystem*)FindSystem( FILESYSTEM_INTERFACE_VERSION );\n'
    + T + 'CSARM_LOGI( "Create: FindSystem(fs)=%p", (void*)pFileSystem );\n'
    + T + 'pFileSystem->InstallDirtyDiskReportFunc( ReportDirtyDiskNoMaterialSystem );\n'))

pairs.append((
    T + 'if ( !AddSystems( appSystems ) ) \n'
    + T + '\treturn false;\n',
    T + 'if ( !AddSystems( appSystems ) ) \n'
    + T + '{\n'
    + T + '\tCSARM_LOGW( "Create: AddSystems FAILED" );\n'
    + T + '\treturn false;\n'
    + T + '}\n'
    + T + 'CSARM_LOGI( "Create: AddSystems OK" );\n'))

pairs.append((
    'bool CSourceAppSystemGroup::PreInit()\n{\n'
    + T + 'CreateInterfaceFn factory = GetFactory();\n',
    'bool CSourceAppSystemGroup::PreInit()\n{\n'
    + T + 'CSARM_LOGI( "PreInit enter" );\n'
    + T + 'CreateInterfaceFn factory = GetFactory();\n'))

pairs.append((
    T + 'if ( !g_pFullFileSystem || !g_pMaterialSystem )\n'
    + T + '\treturn false;\n',
    T + 'if ( !g_pFullFileSystem || !g_pMaterialSystem )\n'
    + T + '{\n'
    + T + '\tCSARM_LOGW( "PreInit FAILED: no filesystem/materialsystem factory" );\n'
    + T + '\treturn false;\n'
    + T + '}\n'))

pairs.append((
    T + 'if ( FileSystem_SetupSteamEnvironment( steamInfo ) != FS_OK )\n'
    + T + '\treturn false;\n',
    T + 'if ( FileSystem_SetupSteamEnvironment( steamInfo ) != FS_OK )\n'
    + T + '{\n'
    + T + '\tCSARM_LOGW( "PreInit FAILED: SetupSteamEnvironment" );\n'
    + T + '\treturn false;\n'
    + T + '}\n'))

pairs.append((
    T + 'if ( FileSystem_MountContent( fsInfo ) != FS_OK )\n'
    + T + '\treturn false;\n',
    T + 'if ( FileSystem_MountContent( fsInfo ) != FS_OK )\n'
    + T + '{\n'
    + T + '\tCSARM_LOGW( "PreInit FAILED: MountContent" );\n'
    + T + '\treturn false;\n'
    + T + '}\n'))

pairs.append((
    T + 'return g_pEngineAPI->SetStartupInfo( info );\n}\n',
    T + 'CSARM_LOGI( "PreInit OK -> SetStartupInfo" );\n'
    + T + 'return g_pEngineAPI->SetStartupInfo( info );\n}\n'))

pairs.append((
    'int CSourceAppSystemGroup::Main()\n{\n'
    + T + 'return g_pEngineAPI->Run();\n}\n',
    'int CSourceAppSystemGroup::Main()\n{\n'
    + T + 'CSARM_LOGI( "Main -> CEngineAPI::Run" );\n'
    + T + 'return g_pEngineAPI->Run();\n}\n'))

pairs.append((
    T + '\t' + 'int nRetval = steamApplication.Run();\n',
    T + '\t' + 'int nRetval = steamApplication.Run();\n'
    + T + '\t' + 'CSARM_LOGI( "LauncherMain: steamApplication.Run() returned %d (stage=%d)", nRetval, (int)steamApplication.GetCurrentStage() );\n'))

orig = text
text = apply(text, 'launcher.cpp', pairs)
out.append(unified(orig, text, 'launcher/launcher.cpp'))

# ---------------------------------------------------------------- sys_dll2.cpp
text = open(os.path.join(tmp, 'sys_dll2.cpp')).read()
pairs = []
pairs.append((
    '#include "engine_launcher_api.h"\n#include "ivideomode.h"\n',
    '#include "engine_launcher_api.h"\n#include "ivideomode.h"\n#include "common/csarm_log.h"\n'))
pairs.append((
    'int CEngineAPI::Run()\n{\n'
    + T + 'if ( CommandLine()->FindParm("-insecure") )',
    'int CEngineAPI::Run()\n{\n'
    + T + 'CSARM_LOGI( "CEngineAPI::Run enter" );\n'
    + T + 'if ( CommandLine()->FindParm("-insecure") )'))
pairs.append((
    'int CEngineAPI::RunListenServer()\n{\n',
    'int CEngineAPI::RunListenServer()\n{\n'
    + T + 'CSARM_LOGI( "CEngineAPI::RunListenServer enter" );\n'))
orig = text
text = apply(text, 'sys_dll2.cpp', pairs)
out.append(unified(orig, text, 'engine/sys_dll2.cpp'))

# ---------------------------------------------------------------- sdlmgr.cpp
# CSDLMgr::Init creates a hidden 640x480 GL window; on Android SDL 2.0.2
# cannot make that window's GL context from the SDLThread (no Java surface
# wired) -> SDL_CreateWindow/SDL_GL path segfaults (run 41131384551,
# CSDLMgr::CreateHiddenGameWindow+737, fault 0x3d8).  The boot path does not
# present frames yet — skip the hidden window under __ANDROID__.
text = open(os.path.join(tmp, 'sdlmgr.cpp')).read()
pairs = []
pairs.append((
    '// NOTE: This has to be the last file included! (turned off below, since this is included like a header)\n#include "tier0/memdbgon.h"\n',
    '#include "common/csarm_log.h"\n\n'
    '// NOTE: This has to be the last file included! (turned off below, since this is included like a header)\n#include "tier0/memdbgon.h"\n'))
pairs.append((
    T + '// we need a GL context before we dig down further, since we\'re calling\n'
    + T + '//  GL entry points, but the game hasn\'t made a window yet. So it\'s time\n'
    + T + '//  to make a window! We make a 640x480 one here, and later, when asked\n'
    + T + '//  to really actually make a window, we just resize the one we built here.\n'
    + '    if ( !CreateHiddenGameWindow( "", true, 640, 480 ) )\n'
    + T + T + 'Error( "CreateGameWindow failed" );\n'
    + '\n'
    + T + 'if ( !m_bTextMode )\n'
    + T + T + 'SDL_HideWindow( m_Window );\n',
    T + '#ifdef __ANDROID__\n'
    + T + '// csARM: the hidden GL window needs a Java-side surface that SDL 2.0.2\n'
    + T + '// cannot wire up from this thread; the boot path does not present frames.\n'
    + T + 'CSARM_LOGI( "SDLMgr: skip hidden game window (Android)" );\n'
    + T + '#else\n'
    + T + '// we need a GL context before we dig down further, since we\'re calling\n'
    + T + '//  GL entry points, but the game hasn\'t made a window yet. So it\'s time\n'
    + T + '//  to make a window! We make a 640x480 one here, and later, when asked\n'
    + T + '//  to really actually make a window, we just resize the one we built here.\n'
    + '    if ( !CreateHiddenGameWindow( "", true, 640, 480 ) )\n'
    + T + T + 'Error( "CreateGameWindow failed" );\n'
    + '\n'
    + T + 'if ( !m_bTextMode )\n'
    + T + T + 'SDL_HideWindow( m_Window );\n'
    + T + '#endif\n'))
orig = text
text = apply(text, 'sdlmgr.cpp', pairs)
out.append(unified(orig, text, 'appframework/sdlmgr.cpp'))

# ---------------------------------------------------------------- threadtools.inl
# CThread::Join (POSIX): pthread_join on an already-joined pthread_t ABORTS the
# process on bionic ("invalid pthread_t passed to pthread_join", glibc only
# returns ESRCH).  CThreadPool::Stop joins the raw zombie handle and the
# CThread destructor then joins m_threadZombieId a second time.  Consume BOTH
# handle slots before the join so no second join of the same thread is possible.
text = open(os.path.join(tmp, 'threadtools.inl')).read()
pairs = []
pairs.append((
    T + T + 'bool ret = ThreadJoin(  (ThreadHandle_t)(m_threadId ? m_threadId : m_threadZombieId), timeout );\n'
    + T + T + 'm_threadZombieId = 0;\n'
    + T + T + 'return ret;\n',
    T + T + '// csARM (bionic): pthread_join of an already-joined handle aborts the\n'
    + T + T + '// process. Consume both handle slots BEFORE joining so a second\n'
    + T + T + '// Join()/destructor call can never re-join the same pthread.\n'
    + T + T + 'ThreadHandle_t hJoin = (ThreadHandle_t)(m_threadId ? m_threadId : m_threadZombieId);\n'
    + T + T + 'm_threadId = 0;\n'
    + T + T + 'm_threadZombieId = 0;\n'
    + T + T + 'if ( !hJoin )\n'
    + T + T + T + 'return true;\n'
    + T + T + 'bool ret = ThreadJoin( hJoin, timeout );\n'
    + T + T + 'return ret;\n'))
orig = text
text = apply(text, 'threadtools.inl', pairs)
out.append(unified(orig, text, 'public/tier0/threadtools.inl'))

# ---------------------------------------------------------------- jobthread.cpp
# CThreadPool::Stop: joins the raw pthread handle captured before the exit
# handshake; the CThread destructor afterwards sees a stale m_threadZombieId
# and joins the SAME handle again -> SIGABRT on bionic (run 41154407280,
# CThread::~CThread <- CThreadPool::Stop <- CBaseFileSystem::Shutdown).
text = open(os.path.join(tmp, 'jobthread.cpp')).read()
pairs = []
pairs.append((
    T + T + 'if ( arrHandles[i] )\n'
    + T + T + '{\n'
    + T + T + T + 'ThreadJoin( arrHandles[i] );\n',
    T + T + 'if ( arrHandles[i] )\n'
    + T + T + '{\n'
    + T + T + T + '// csARM (bionic): joining the raw handle leaves the CThread zombie\n'
    + T + T + T + '// bookkeeping set; the destructor then joins the SAME pthread a\n'
    + T + T + T + '// second time and bionic aborts ("invalid pthread_t"). The object\n'
    + T + T + T + '// Join() consumes its handle slots, so the destructor is a no-op.\n'
    + T + T + T + 'm_Threads[i]->Join();\n'))
orig = text
text = apply(text, 'jobthread.cpp', pairs)
out.append(unified(orig, text, 'vstdlib/jobthread.cpp'))

# ---------------------------------------------------------------- descriptor.cc
# protobuf 2.5.0 DescriptorPool::InternalAddGeneratedFile GOOGLE_CHECKs the
# EncodedDescriptorDatabase::Add result.  Valve's build links protobuf
# STATICALLY into every DLL — each DLL owns a private descriptor pool and the
# same file registered twice never meets.  Our libprotobuf.so is SHARED, so
# engine/client/server all register the same generated files into ONE pool
# and the second registration trips the GOOGLE_CHECK -> LogMessage FATAL ->
# Plat_ExitProcess(0) — the clean exit(0) that killed the boot at
# System.loadLibrary("client") (run 41211027894: backtrace
# protobuf_AddDesc_base_5fgcmessages -> InternalAddGeneratedFile ->
# LogMessage::Finish -> Plat_ExitProcess).
text = open(os.path.join(tmp, 'descriptor.cc')).read()
pairs = []
pairs.append((
    '  InitGeneratedPoolOnce();\n'
    '  GOOGLE_CHECK(generated_database_->Add(encoded_file_descriptor, size));\n'
    '}\n',
    '  InitGeneratedPoolOnce();\n'
    '  // csARM: one shared libprotobuf.so serves every module; each module\'s\n'
    '  // generated AddDescriptors() re-registers the same files.  Valve\'s\n'
    '  // per-DLL static protobuf never saw this — re-registration is a no-op.\n'
    '  if ( !generated_database_->Add( encoded_file_descriptor, size ) )\n'
    '  {\n'
    '    return;\n'
    '  }\n'
    '}\n'))
orig = text
text = apply(text, 'descriptor.cc', pairs)
out.append(unified(orig, text, 'thirdparty/protobuf-2.5.0/src/google/protobuf/descriptor.cc'))

# ---------------------------------------------------------------- message.cc
# protobuf 2.5.0 MessageFactory::InternalRegisterGeneratedFile ->
# GeneratedMessageFactory::RegisterFile GOOGLE_LOG(FATAL)s on duplicate file
# registration ("File is already registered"), and RegisterType DFATALs on
# duplicate types.  With the SHARED libprotobuf.so the same generated pb.cc
# is embedded in engine, client AND server — the first duplicate file kills
# the process with a clean exit(0) via the tier0 exit interposer (run
# 41215315729: protobuf_AddDesc_base_5fgcmessages ->
# protobuf_AddDesc_steammessages -> InternalRegisterGeneratedFile ->
# LogMessage::Finish -> exit(0), the boot never reached LauncherMain).
# Valve's STATIC per-DLL protobuf never hit this.  Make both a no-op:
# first module wins, identical generated types are reused.
text = open(os.path.join(tmp, 'message.cc')).read()
pairs = []
pairs.append((
    'void GeneratedMessageFactory::RegisterFile(\n'
    '    const char* file, RegistrationFunc* registration_func) {\n'
    '  if (!InsertIfNotPresent(&file_map_, file, registration_func)) {\n'
    '    GOOGLE_LOG(FATAL) << "File is already registered: " << file;\n'
    '  }\n'
    '}\n',
    'void GeneratedMessageFactory::RegisterFile(\n'
    '    const char* file, RegistrationFunc* registration_func) {\n'
    '  // csARM: one shared libprotobuf.so serves every module; engine, client\n'
    '  // and server each embed the same generated pb.cc and register the same\n'
    '  // files into the SINGLE factory singleton.  Valve links protobuf STATIC\n'
    '  // per-DLL so every DLL owned a private factory and never met the\n'
    '  // duplicate.  GOOGLE_LOG(FATAL) here killed the boot at\n'
    '  // System.loadLibrary("client") with a clean exit(0) (run 41215315729:\n'
    '  // protobuf_AddDesc_base_5fgcmessages -> protobuf_AddDesc_steammessages\n'
    '  // -> InternalRegisterGeneratedFile -> LogMessage::Finish -> exit(0)).\n'
    '  // First module wins; later registrations are a no-op.\n'
    '  if (!InsertIfNotPresent(&file_map_, file, registration_func))\n'
    '  {\n'
    '    return;\n'
    '  }\n'
    '}\n'))
pairs.append((
    '  mutex_.AssertHeld();\n'
    '  if (!InsertIfNotPresent(&type_map_, descriptor, prototype)) {\n'
    '    GOOGLE_LOG(DFATAL) << "Type is already registered: " << descriptor->full_name();\n'
    '  }\n'
    '}\n',
    '  mutex_.AssertHeld();\n'
    '  // csARM: see RegisterFile above — duplicate type registration (shared\n'
    '  // libprotobuf.so, NDEBUG not defined so DFATAL == FATAL) must not kill\n'
    '  // the process; first module wins.\n'
    '  if (!InsertIfNotPresent(&type_map_, descriptor, prototype))\n'
    '  {\n'
    '    return;\n'
    '  }\n'
    '}\n'))
orig = text
text = apply(text, 'message.cc', pairs)
out.append(unified(orig, text, 'thirdparty/protobuf-2.5.0/src/google/protobuf/message.cc'))

# ---------------------------------------------------------------- write
NEW_FILE_HUNK = ('diff --git a/common/csarm_log.h b/common/csarm_log.h\n'
                 'new file mode 100644\n'
                 '--- /dev/null\n'
                 '+++ b/common/csarm_log.h\n'
                 '@@ -0,0 +1,17 @@\n'
                 + ''.join(('+' + ln + '\n') if ln else '+\n'
                           for ln in CSARM_LOG_H.split('\n')[:-1]))

diff_path = os.path.join(repo, 'patches/extras/csarm_boot.diff')
old_diff = open(diff_path).read()
# keep only the original sys_engine hunk: everything before the first
# generated 'diff --git' section (previous runs may have appended sections)
base = old_diff.split('\ndiff --git')[0].rstrip('\n')
open(diff_path, 'w').write(base + '\n' + NEW_FILE_HUNK + '\n'.join(out))
print(f'csarm_boot.diff regenerated: base={len(base)}B probes={sum(len(x) for x in out)}B')
