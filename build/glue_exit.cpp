// csARM — exit-path interposer for boot diagnosis.
//
// Run 41198597552: libclient.so now dlopen's clean (all relocations resolve)
// and its static initializers run for the first time — one of them ends the
// process with a clean exit(0) before CSARM_LOAD_DONE ever prints.  Interpose
// the three process-exit entry points (exit, _exit, pthread_exit) in libtier0
// (the first Valve lib loaded by BOTH test activities, DT_NEEDED of every
// port lib — bionic resolves the caller's UND through its own DT_NEEDED
// closure BEFORE the global group, so our interposer wins).  CSARM_EXIT_HIT +
// CSARM_EXIT_BT backtrace lines land in the CI artifact and name the caller;
// the real libc function is reached via RTLD_NEXT.
//
// NOTE: backtrace/backtrace_symbols are declared here manually — the NDK's
// <execinfo.h> does not expose them at this API level (compile failed in run
// 41202789926), but libc.so exports both.
#include <dlfcn.h>
#include <unistd.h>
#include <android/log.h>

extern "C" {
int backtrace( void **array, int size );
typedef void (*exit_fn_t)(int);
typedef void (*pthread_exit_fn_t)(void *);
}

static void csarm_log_exit( const char *what, int code )
{
	void *bt[48];
	int n = backtrace( bt, 48 );
	__android_log_print( ANDROID_LOG_ERROR, "CSARM",
		"CSARM_EXIT_HIT %s code=%d depth=%d", what, code, n );
	for ( int i = 0; i < n; i++ )
		__android_log_print( ANDROID_LOG_ERROR, "CSARM",
			"CSARM_EXIT_BT %02d %p", i, bt[i] );
}

extern "C" __attribute__((noreturn)) void exit( int code )
{
	csarm_log_exit( "exit", code );
	volatile exit_fn_t real = (exit_fn_t)dlsym( RTLD_NEXT, "exit" );
	if ( real )
		real( code );
	_exit( code );
}

extern "C" __attribute__((noreturn)) void _exit( int code )
{
	csarm_log_exit( "_exit", code );
	volatile exit_fn_t real = (exit_fn_t)dlsym( RTLD_NEXT, "_exit" );
	if ( real )
		real( code );
	for (;;) __asm__ volatile("");
}

extern "C" __attribute__((noreturn)) void pthread_exit( void *retval )
{
	csarm_log_exit( "pthread_exit", 0 );
	volatile pthread_exit_fn_t real =
		(pthread_exit_fn_t)dlsym( RTLD_NEXT, "pthread_exit" );
	if ( real )
		real( retval );
	_exit( 0 );
}
