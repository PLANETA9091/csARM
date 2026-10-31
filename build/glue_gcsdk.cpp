// csARM — GCSDK out-of-line stubs for the game DLLs.
//
// cstrike15_src ships only the gcsdk HEADERS (public/gcsdk/*.h); the real
// implementations live in the Steam SDK and are absent from the mirror.  The
// game DLLs still reference the out-of-line members — run 41190437631:
// libserver dlopen died at GCSDK::CJob::~CJob, 25+ GCSDK UNDs total.
//
// Deliberately NO Valve headers here: the gcsdk include chain does not
// compile standalone (common/reliabletimer.h expects k_nMillion from its
// includer, workthreadpool.h needs <refcount.h> via a -I the game build
// never exercises).  Instead each needed symbol is declared with minimal
// local classes whose SIGNATURES are copied verbatim from the real headers
// — mangled names match the und-gate report exactly.  Defining the virtual
// destructors makes this TU emit the vtables/typeinfo the game DLLs
// reference (_ZTI/_ZTV GCSDK::...).  Boot never talks to a GC, so no-op
// bodies are sufficient; method bodies that run would be a later port.
//
// Compiled once per game DLL (client+server), like Valve's own static
// GCSDK lib would be.

#include <stddef.h>
#include <stdint.h>
typedef unsigned int uint;
#include <stdint.h>
#include <string>

namespace google { namespace protobuf { class Message; } }

// Valve tier1 types — GLOBAL namespace (mangling!); pointer/ref only
class CUtlBuffer;

namespace GCSDK
{

// ------------------------------------------------------------------ forward
class CJobMgr;
class CSharedObject;
class CSharedObjectTypeCache;
class IMsgNetPacket;

// CGCEmitGroup: the real class carries convar members; the game only takes
// SPEW_GC's address and passes const refs to EmitWarning.
class CGCEmitGroup
{
public:
	const char *m_pszGroupName;
};

// SPEW_GC is referenced by address (_ZN5GCSDK7SPEW_GCE).
CGCEmitGroup SPEW_GC = { "GC" };

// EmitWarning: routed through nothing (no engine headers here) — the varargs
// sink keeps the signature exact and drops the text.
void EmitWarning( const CGCEmitGroup &Group, int iLevel, const char *pchMsg, ... )
{
	(void)Group; (void)iLevel; (void)pchMsg;
}

// --------------------------------------------------------------------- CJob
class CJob
{
public:
	explicit CJob( CJobMgr &jobMgr, char const *pchJobName = NULL );
	virtual ~CJob();
	bool BYieldingWaitOneFrame();
};

CJob::CJob( CJobMgr &jobMgr, char const *pchJobName )
{
	(void)jobMgr; (void)pchJobName;
}

CJob::~CJob() {}

bool CJob::BYieldingWaitOneFrame()
{
	return false;
}

// ------------------------------------------------------------------- CJobMgr
struct JobType_t;  // real decl in jobmgr.h — pointer/ref only

class CJobMgr
{
public:
	static void RegisterJobType( const JobType_t *pJobType );
};

void CJobMgr::RegisterJobType( const JobType_t *pJobType )
{
	(void)pJobType;
}

// ------------------------------------------------------------- CSharedObject
typedef CSharedObject *( *SOCreationFunc_t )();

class CSharedObject
{
public:
	virtual ~CSharedObject();   // key function: emits _ZTV/_ZTI CSharedObject
	static void RegisterFactory( int nTypeID, SOCreationFunc_t fnFactory, uint32_t unFlags,
	                             const char *pchClassName, const char *pchBuildCacheName,
	                             const char *pchCreateName, const char *pchUpdateName );
	static CSharedObject *Create( int nTypeID );
};

CSharedObject::~CSharedObject() {}

void CSharedObject::RegisterFactory( int nTypeID, SOCreationFunc_t fnFactory, uint32_t unFlags,
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
class CSharedObjectCache
{
public:
	virtual ~CSharedObjectCache();
	CSharedObject *FindSharedObject( const CSharedObject &soIndex );
	CSharedObjectTypeCache *FindBaseTypeCache( int nClassID );
};

CSharedObjectCache::~CSharedObjectCache() {}

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

// ------------------------------------------------- CProtoBufSharedObjectBase
class CProtoBufSharedObjectBase : public CSharedObject
{
public:
	virtual ~CProtoBufSharedObjectBase();
	bool BParseFromMessage( const CUtlBuffer &buffer );
	bool BParseFromMessage( const std::string &buffer );
	bool BUpdateFromNetwork( const CSharedObject &objUpdate );
	void Copy( const CSharedObject &objUpdate );
	static void Dump( const ::google::protobuf::Message &msg );
	bool BIsKeyLess( const CSharedObject &soRHS ) const;
	bool BAddToMessage( std::string *pBuffer ) const;
	bool BAddDestroyToMessage( std::string *pBuffer ) const;
	void Dump() const;
};

CProtoBufSharedObjectBase::~CProtoBufSharedObjectBase() {}

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

void CProtoBufSharedObjectBase::Dump() const {}

// ---------------------------------------------------------- CProtoBufMsgBase
class CThreadMutexStub   // storage type for the static member; name not mangled
{
public:
	void *m_pad[ 8 ];
};

class CProtoBufMsgBase
{
public:
	CProtoBufMsgBase();
	virtual ~CProtoBufMsgBase();   // out-of-line: key function emits _ZTV/_ZTI
	bool InitFromPacket( IMsgNetPacket *pNetPacket );
	static CThreadMutexStub s_PoolRegMutex;
};

CProtoBufMsgBase::CProtoBufMsgBase() {}
CProtoBufMsgBase::~CProtoBufMsgBase() {}
CThreadMutexStub CProtoBufMsgBase::s_PoolRegMutex;

bool CProtoBufMsgBase::InitFromPacket( IMsgNetPacket *pNetPacket )
{
	(void)pNetPacket;
	return false;
}

// --------------------------------------------------- CProtoBufMsgMemoryPool*
class CProtoBufMsgMemoryPoolBase
{
public:
	CProtoBufMsgMemoryPoolBase( uint32_t unTargetLow, uint32_t unTargetHigh );
	virtual ~CProtoBufMsgMemoryPoolBase();
	::google::protobuf::Message *Alloc();
	void Free( ::google::protobuf::Message *pMsg );
	bool PopItem( ::google::protobuf::Message **ppMsg );
};

CProtoBufMsgMemoryPoolBase::CProtoBufMsgMemoryPoolBase( uint32_t unTargetLow, uint32_t unTargetHigh )
{
	(void)unTargetLow; (void)unTargetHigh;
}

CProtoBufMsgMemoryPoolBase::~CProtoBufMsgMemoryPoolBase() {}

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

class CProtoBufMsgMemoryPoolMgr
{
public:
	CProtoBufMsgMemoryPoolMgr();
	void RegisterPool( CProtoBufMsgMemoryPoolBase *pPool );
};

CProtoBufMsgMemoryPoolMgr::CProtoBufMsgMemoryPoolMgr() {}

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
