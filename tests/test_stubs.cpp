// csARM qemu/host math test harness stubs.
// The test links mathlib sources only; these are the few tier0/tier1/vstdlib
// entry points mathlib references. Implementations are minimal on purpose:
// the harness only exercises math, not logging, allocation fidelity or RNG
// distribution.
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <malloc.h>
#include "tier0/platform.h"
#include "tier0/memalloc.h"

// ---- tier0 dbg (Msg/Warning/Error) ----
extern "C" void Msg( PRINTF_FORMAT_STRING const char *pMsg, ... )
{
	va_list args;
	va_start( args, pMsg );
	vprintf( pMsg, args );
	va_end( args );
}

extern "C" void Warning( PRINTF_FORMAT_STRING const char *pMsg, ... ) {}

extern "C" void Error( PRINTF_FORMAT_STRING const char *pMsg, ... )
{
	va_list args;
	va_start( args, pMsg );
	vfprintf( stderr, pMsg, args );
	va_end( args );
	exit( 1 );
}

extern "C" void ThreadSleep( unsigned duration )
{
	// busy stub: harness is single-threaded
}

// ---- minimal IMemAlloc backed by malloc ----
class CTestMemAlloc : public IMemAlloc
{
public:
	virtual const char* GetMemoryName() const { return "test-malloc"; }
	virtual size_t GetAllocatedBytes() const { return 0; }
	virtual size_t GetCommittedBytes() const { return 0; }
	virtual size_t GetReservedBytes() const { return 0; }
	virtual size_t GetHighestBytes() const { return 0; }

	virtual void *Alloc( size_t nSize ) { return malloc( nSize ); }
	virtual void *Realloc( void *pMem, size_t nSize ) { return realloc( pMem, nSize ); }
	virtual void Free( void *pMem ) { free( pMem ); }
	virtual void *Expand_NoLongerSupported( void *pMem, size_t nSize ) { return NULL; }

	virtual void *Alloc( size_t nSize, const char *pFileName, int nLine ) { return Alloc( nSize ); }
	virtual void *Realloc( void *pMem, size_t nSize, const char *pFileName, int nLine ) { return Realloc( pMem, nSize ); }
	virtual void Free( void *pMem, const char *pFileName, int nLine ) { Free( pMem ); }
	virtual void *Expand_NoLongerSupported( void *pMem, size_t nSize, const char *pFileName, int nLine ) { return NULL; }

	virtual void *AllocAlign( size_t nSize, size_t align )
	{
		void *p = NULL;
		if ( posix_memalign( &p, align < sizeof(void*) ? sizeof(void*) : align, nSize ) != 0 )
			return NULL;
		return p;
	}
	virtual void *AllocAlign( size_t nSize, size_t align, const char *pFileName, int nLine ) { return AllocAlign( nSize, align ); }
	virtual void *ReallocAlign( void *pMem, size_t nSize, size_t align )
	{
		void *p = AllocAlign( nSize, align );
		if ( p && pMem ) { memcpy( p, pMem, nSize ); Free( pMem ); }
		return p;
	}

	virtual size_t GetSize( void *pMem ) { return pMem ? malloc_usable_size( pMem ) : 0; }
	virtual void PushAllocDbgInfo( const char *pFileName, int nLine ) {}
	virtual void PopAllocDbgInfo() {}
	virtual int32 CrtSetBreakAlloc( int32 lNewBreakAlloc ) { return 0; }
	virtual int CrtSetReportMode( int nReportType, int nReportMode ) { return 0; }
	virtual int CrtIsValidHeapPointer( const void *pMem ) { return 1; }
	virtual int CrtIsValidPointer( const void *pMem, unsigned int size, int access ) { return 1; }
	virtual int CrtCheckMemory( void ) { return 1; }
	virtual int CrtSetDbgFlag( int nNewFlag ) { return 0; }
	virtual void CrtMemCheckpoint( _CrtMemState *pState ) {}
	virtual void DumpStats() {}
	virtual void DumpStatsFileBase( char const *pchFileBase, DumpStatsFormat_t nFormat ) {}
	virtual size_t ComputeMemoryUsedBy( char const *pchSubStr ) { return 0; }
	virtual void* CrtSetReportFile( int nRptType, void* hFile ) { return NULL; }
	virtual void* CrtSetReportHook( void* pfnNewHook ) { return NULL; }
	virtual int CrtDbgReport( int nRptType, const char *szFile, int nLine, const char *pModuleName, const char *pMessage ) { return 0; }
	virtual int heapchk() { return 0; }
	virtual bool IsDebugHeap() { return false; }
	virtual void GetActualDbgInfo( const char *&pFileName, int &nLine ) {}
	virtual void RegisterAllocation( const char *pFileName, int nLine, size_t nLogicalSize, size_t nActualSize, unsigned nTime ) {}
	virtual void RegisterDeallocation( const char *pFileName, int nLine, size_t nLogicalSize, size_t nActualSize, unsigned nTime ) {}
	virtual int GetVersion() { return 1; }
	virtual void CompactHeap() {}
	virtual MemAllocFailHandler_t SetAllocFailHandler( MemAllocFailHandler_t pfn ) { return pfn; }
	virtual void DumpBlockStats( void * ) {}
	virtual void SetStatsExtraInfo( const char *pMapName, const char *pComment ) {}
	virtual size_t MemoryAllocFailed() { return 0; }
	virtual void CompactIncremental() {}
	virtual void OutOfMemory( size_t nBytesAttempted ) {}
	virtual void *RegionAlloc( int region, size_t nSize ) { return Alloc( nSize ); }
	virtual void *RegionAlloc( int region, size_t nSize, const char *pFileName, int nLine ) { return Alloc( nSize ); }

	virtual void GlobalMemoryStatus( size_t *pUsedMemory, size_t *pFreeMemory )
	{
		if ( pUsedMemory ) *pUsedMemory = 0;
		if ( pFreeMemory ) *pFreeMemory = 0;
	}
	virtual IVirtualMemorySection *AllocateVirtualMemorySection( size_t numMaxBytes ) { return NULL; }
	virtual int GetGenericMemoryStats( GenericMemoryStat_t **ppMemoryStats ) { if ( ppMemoryStats ) *ppMemoryStats = NULL; return 0; }
	virtual uint32 GetDebugInfoSize() { return 0; }
	virtual void SaveDebugInfo( void *pvDebugInfo ) {}
	virtual void RestoreDebugInfo( const void *pvDebugInfo ) {}
	virtual void InitDebugInfo( void *pvDebugInfo, const char *pchRootFileName, int nLine ) {}
};

static CTestMemAlloc s_TestMemAlloc;
IMemAlloc *g_pMemAlloc = &s_TestMemAlloc;


// ---- tier1 string helpers referenced by convar.cpp ----
#include "characterset.h"
#include "tier1/strtools.h"

// strtools.cpp pulls the whole logging/thread stack into the harness; these
// wrappers cover the handful of symbols convar.cpp actually needs.
void _V_memset( void *dest, int fill, int count ) { memset( dest, fill, count ); }
void _V_memcpy( void *dest, const void *src, int count ) { memcpy( dest, src, count ); }
void _V_memmove( void *dest, const void *src, int count ) { memmove( dest, src, count ); }
int _V_memcmp( const void *m1, const void *m2, int count ) { return memcmp( m1, m2, count ); }
int _V_strlen( const char *str ) { return (int)strlen( str ); }
int _V_strnlen( const char *str, int count ) { int n = 0; while ( n < count && str[n] ) n++; return n; }
int _V_strcmp( const char *s1, const char *s2 ) { return strcmp( s1, s2 ); }
int _V_strncmp( const char *s1, const char *s2, int count ) { return strncmp( s1, s2, count ); }
int _V_stricmp( const char *s1, const char *s2 ) { return strcasecmp( s1, s2 ); }
int _V_strnicmp( const char *s1, const char *s2, int n ) { return strncasecmp( s1, s2, n ); }
double V_atod( const char *str ) { return atof( str ); }
int V_strncmp( const char *s1, const char *s2, int count ) { return strncmp( s1, s2, count ); }
const char *V_strnistr( const char *pStr, const char *pSearch, int n )
{
	size_t nl = strlen( pSearch );
	for ( ; n > 0 && *pStr && (int)nl <= n; pStr++, n-- )
	{
		if ( !strncasecmp( pStr, pSearch, nl ) ) return pStr;
	}
	return NULL;
}
const char *V_strnchr( const char *pStr, char c, int n )
{
	for ( ; n > 0 && *pStr; pStr++, n-- )
	{
		if ( *pStr == c ) return pStr;
	}
	return NULL;
}
char *_V_strstr( const char *s1, const char *s2 ) { return (char*)strstr( s1, s2 ); }
char *_V_strchr( const char *s, int c ) { return (char*)strchr( s, c ); }
char *_V_strrchr( const char *s, int c ) { return (char*)strrchr( s, c ); }
const char *V_stristr( const char *pStr, const char *pSearch )
{
	size_t nl = strlen( pSearch );
	for ( ; *pStr; pStr++ )
	{
		if ( !strncasecmp( pStr, pSearch, nl ) ) return pStr;
	}
	return NULL;
}
int V_vsnprintf( char *pDest, int maxLen, const char *pFormat, va_list args )
{
	int r = vsnprintf( pDest, maxLen, pFormat, args );
	return ( r >= maxLen ) ? -1 : r;
}
int V_vsnprintfSize( const char *pFormat, va_list args ) { return vsnprintf( NULL, 0, pFormat, args ); }
bool V_StringMatchesPattern( const char *szString, const char *szPattern, int flags )
{
	// simple '*' wildcard matcher, enough for the harness
	if ( !szString || !szPattern ) return false;
	const char *s = szString, *p = szPattern;
	const char *starS = NULL, *starP = NULL;
	while ( *s )
	{
		if ( *p == '?' || strncasecmp( s, p, 1 ) == 0 ) { s++; p++; }
		else if ( *p == '*' ) { starS = s; starP = ++p; }
		else if ( starP ) { s = ++starS; p = starP; }
		else return false;
	}
	while ( *p == '*' ) p++;
	return *p == 0;
}
int V_StrTrim( char *pStr )
{
	if ( !pStr || !*pStr ) return 0;
	char *s = pStr;
	while ( *s == ' ' || *s == '\t' || *s == '\n' || *s == '\r' ) s++;
	char *e = s + strlen( s );
	while ( e > s && ( e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\n' || e[-1] == '\r' ) ) e--;
	memmove( pStr, s, e - s );
	pStr[e - s] = 0;
	return (int)( e - s );
}
const char *V_UnqualifiedFileName( const char *in )
{
	const char *r = strrchr( in, '/' );
	return r ? r + 1 : in;
}
void V_MakeAbsolutePath( char *pOut, int outLen, const char *pPath, const char *pStartingDir )
{
	if ( pPath[0] == '/' ) { strncpy( pOut, pPath, outLen ); }
	else
	{
		snprintf( pOut, outLen, "%s/%s", pStartingDir ? pStartingDir : ".", pPath );
	}
}
bool V_ExtractFilePath( const char *path, char *dest, int destSize )
{
	strncpy( dest, path, destSize );
	char *r = strrchr( dest, '/' );
	if ( r ) *r = 0; else dest[0] = 0;
	return true;
}
bool V_StripLastDir( char *pchPath, int maxLen )
{
	char *r = strrchr( pchPath, '/' );
	if ( r ) *(r + 1) = 0; else pchPath[0] = 0;
	return r != NULL;
}
void V_StripTrailingSlash( char *pchPath )
{
	int len = strlen( pchPath );
	if ( len > 0 && ( pchPath[len-1] == '/' || pchPath[len-1] == '\\' ) )
		pchPath[len-1] = 0;
}
void V_StripExtension( const char *in, char *out, int outLen )
{
	int i = strlen( in ) - 1;
	for ( ; i >= 0 && in[i] != '/' && in[i] != '.'; i-- ) {}
	if ( i >= 0 && in[i] == '.' ) { strncpy( out, in, i < outLen ? i : outLen ); out[ i < outLen ? i : outLen - 1 ] = 0; }
	else strncpy( out, in, outLen );
}
void V_FileBase( const char *in, char *out, int outLen )
{
	const char *b = strrchr( in, '/' );
	b = b ? b + 1 : in;
	const char *dot = strrchr( b, '.' );
	int n = dot && strrchr( b, '/' ) < dot ? (int)( dot - b ) : (int)strlen( b );
	if ( n >= outLen ) n = outLen - 1;
	memcpy( out, b, n ); out[n] = 0;
}
void V_ExtractFileExtension( const char *path, char *dest, int destSize )
{
	const char *d = strrchr( path, '.' );
	const char *s = strrchr( path, '/' );
	if ( d && ( !s || d > s ) ) strncpy( dest, d + 1, destSize );
	else dest[0] = 0;
}
void V_ComposeFileName( const char *path, const char *filename, char *dest, int destSize )
{
	snprintf( dest, destSize, "%s/%s", path, filename );
}
bool V_RemoveDotSlashes( char *pFilename, char separator )
{
	// minimal: collapse duplicate separators
	char *w = pFilename;
	for ( char *r = pFilename; *r; r++ )
	{
		if ( !( *r == separator && w > pFilename && w[-1] == separator ) )
			*w++ = *r;
	}
	*w = 0;
	return true;
}
float V_atof( const char *str ) { return (float)atof( str ); }
int V_atoi( const char *str ) { return atoi( str ); }
char *V_strncat( char *pDest, const char *pSrc, size_t nDestLen, int nMaxCharsToCopy ) { return strncat( pDest, pSrc, nDestLen - strlen( pDest ) - 1 ); }
void V_strncpy( char *pDest, const char *pSrc, int maxLenInChars ) { strncpy( pDest, pSrc, maxLenInChars ); }
void ConMsg( const char *pMsg, ... ) {}

// ---- vstdlib random (simple LCG; vstdlib/random.cpp needs the whole
// threadtools stack, the harness only needs the symbols) ----
static uint32 s_testSeed = 0x12345678u;
extern "C" void RandomSeed( int iSeed ) { s_testSeed = (uint32)iSeed; }
extern "C" float RandomFloat( float flMinVal, float flMaxVal )
{
	s_testSeed = s_testSeed * 1664525u + 1013904223u;
	float t = (float)( s_testSeed >> 8 ) / (float)( 1 << 24 );
	return flMinVal + t * ( flMaxVal - flMinVal );
}
extern "C" float RandomFloatExp( float flMinVal, float flMaxVal, float flExponent )
{
	float f = RandomFloat( flMinVal, flMaxVal );
	return f * f;
}
extern "C" int RandomInt( int nMinVal, int nMaxVal )
{
	s_testSeed = s_testSeed * 1664525u + 1013904223u;
	int r = (int)( s_testSeed >> 1 );
	return nMinVal + ( r % ( nMaxVal - nMinVal + 1 ) );
}
// ---- tier1 cvar registry (link-only; harness never registers cvars) ----
#include "icvar.h"
ICvar *g_pCVar = NULL;

int V_snprintf( char *pDest, int maxLen, const char *pFormat, ... )
{
	va_list args;
	va_start( args, pFormat );
	int r = vsnprintf( pDest, maxLen, pFormat, args );
	va_end( args );
	return r;
}

