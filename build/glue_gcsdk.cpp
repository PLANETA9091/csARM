// csARM — GCSDK out-of-line stubs for the game DLLs.
//
// cstrike15_src ships only the gcsdk HEADERS (public/gcsdk/*.h); the actual
// implementations live in the Steam SDK and are absent from the mirror.  The
// game DLLs still reference the out-of-line members (CJob ctor/dtor,
// CProtoBufMsgBase::InitFromPacket, CSharedObject::RegisterFactory, ... —
// 46+ UND symbols in run 41154407280, which aborted libserver's dlopen at
// GCSDK::CJob::~CJob).  Boot never talks to a GC, so no-op bodies with EXACT
// signatures from the real headers are enough to satisfy dlopen; defining
// the key virtual functions here also makes this TU emit the vtables and
// typeinfo the game DLLs reference (_ZTV/_ZTI GCSDK::...).
//
// Everything is compiled per game DLL (client+server), like Valve's own
// static GCSDK lib would be.

#include "tier0/platform.h"
#include "tier0/dbg.h"
#include <stdarg.h>
#include <stdio.h>
#include "tier1/utlbuffer.h"
#include "gcsdk/gclogger.h"
#include "gcsdk/job.h"
#include "gcsdk/jobmgr.h"
#include "gcsdk/sharedobject.h"
#include "gcsdk/sharedobjectcache.h"
#include "gcsdk/protobufsharedobject.h"
#include "gcsdk/msgprotobuf.h"
#include "gcsdk/netpacket.h"

// memdbgon must be the last include in a Valve source file
#include "tier0/memdbgon.h"

namespace GCSDK
{

// ------------------------------------------------------------------ gclogger
// SPEW_GC is the GC emit group the game DLLs reference; EmitWarning is the
// only spew entry point they call.  Route through the engine Msg/Warning so
// the text lands in logcat like every other CSARM line.
// CGCEmitGroup has no default ctor (name + spew-var names); the GC build
// defines SPEW_GC via DECLARE_GC_EMIT_GROUP. Without GC build members the
// ctor only stores the group name, so empty strings are enough here.
CGCEmitGroup SPEW_GC( "GC", "", "", "", "" );

void EmitWarning( const CGCEmitGroup &Group, int iLevel, const char *pchMsg, ... )
{
        (void)Group;
        (void)iLevel;
        if ( !pchMsg )
                return;
        va_list args;
        va_start( args, pchMsg );
        char szBuf[ 1024 ];
        vsnprintf( szBuf, sizeof( szBuf ), pchMsg, args );
        va_end( args );
        Warning( "GCSDK: %s\n", szBuf );
}

// --------------------------------------------------------------------- CJob
CJob::CJob( CJobMgr &jobMgr, char const *pchJobName )
{
        (void)jobMgr;
        (void)pchJobName;
}

CJob::~CJob()
{
}

bool CJob::BYieldingWaitOneFrame()
{
        return false;
}

// ------------------------------------------------------------------- CJobMgr
void CJobMgr::RegisterJobType( const JobType_t *pJobType )
{
        (void)pJobType;
}

// ------------------------------------------------------------- CSharedObject
void CSharedObject::RegisterFactory( int nTypeID, SOCreationFunc_t fnFactory, uint32 unFlags,
                                     const char *pchClassName, const char *pchBuildCacheName,
                                     const char *pchCreateName, const char *pchUpdateName )
{
        (void)nTypeID; (void)fnFactory; (void)unFlags;
        (void)pchClassName; (void)pchBuildCacheName; (void)pchCreateName; (void)pchUpdateName;
}

CSharedObject *CSharedObject::Create( int nTypeID )
{
        (void)nTypeID;
        return NULL;
}

// -------------------------------------------------------- CSharedObjectCache
CSharedObject *CSharedObjectCache::FindSharedObject( const CSharedObject &soIndex )
{
        (void)soIndex;
        return NULL;
}

CSharedObjectTypeCache *CSharedObjectCache::FindBaseTypeCache( int nClassID )
{
        (void)nClassID;
        return NULL;
}

// ----------------------------------------------- CProtoBufSharedObjectBase
bool CProtoBufSharedObjectBase::BParseFromMessage( const CUtlBuffer &buffer )
{
        (void)buffer;
        return false;
}

bool CProtoBufSharedObjectBase::BParseFromMessage( const std::string &buffer )
{
        (void)buffer;
        return false;
}

bool CProtoBufSharedObjectBase::BUpdateFromNetwork( const CSharedObject &objUpdate )
{
        (void)objUpdate;
        return false;
}

void CProtoBufSharedObjectBase::Copy( const CSharedObject &objUpdate )
{
        (void)objUpdate;
}

void CProtoBufSharedObjectBase::Dump( const ::google::protobuf::Message &msg )
{
        (void)msg;
}

bool CProtoBufSharedObjectBase::BIsKeyLess( const CSharedObject &soRHS ) const
{
        (void)soRHS;
        return false;
}

bool CProtoBufSharedObjectBase::BAddToMessage( std::string *pBuffer ) const
{
        (void)pBuffer;
        return false;
}

bool CProtoBufSharedObjectBase::BAddDestroyToMessage( std::string *pBuffer ) const
{
        (void)pBuffer;
        return false;
}

void CProtoBufSharedObjectBase::Dump() const
{
}

// ---------------------------------------------------------- CProtoBufMsgBase
CProtoBufMsgBase::CProtoBufMsgBase()
{
}

CThreadMutex CProtoBufMsgBase::s_PoolRegMutex;

bool CProtoBufMsgBase::InitFromPacket( IMsgNetPacket *pNetPacket )
{
        (void)pNetPacket;
        return false;
}

// --------------------------------------------------- CProtoBufMsgMemoryPool*
CProtoBufMsgMemoryPoolBase::CProtoBufMsgMemoryPoolBase( uint32 unTargetLow, uint32 unTargetHigh )
        : m_unTargetCountLow( unTargetLow ), m_unTargetCountHigh( unTargetHigh )
{
}

CProtoBufMsgMemoryPoolBase::~CProtoBufMsgMemoryPoolBase()
{
}

::google::protobuf::Message *CProtoBufMsgMemoryPoolBase::Alloc()
{
        return NULL;
}

void CProtoBufMsgMemoryPoolBase::Free( ::google::protobuf::Message *pMsg )
{
        (void)pMsg;
}

bool CProtoBufMsgMemoryPoolBase::PopItem( ::google::protobuf::Message **ppMsg )
{
        if ( ppMsg )
                *ppMsg = NULL;
        return false;
}

CProtoBufMsgMemoryPoolMgr::CProtoBufMsgMemoryPoolMgr()
{
}

void CProtoBufMsgMemoryPoolMgr::RegisterPool( CProtoBufMsgMemoryPoolBase *pPool )
{
        (void)pPool;
}

CProtoBufMsgMemoryPoolMgr *GProtoBufMsgMemoryPoolMgr()
{
        static CProtoBufMsgMemoryPoolMgr s_Mgr;
        return &s_Mgr;
}

} // namespace GCSDK
