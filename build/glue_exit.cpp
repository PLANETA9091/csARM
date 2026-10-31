// csARM — exit-path interposer for boot diagnosis.
//
// libclient.so now dlopen's clean and its static initializers run for the
// first time; one of them ends the process with a clean exit(0) before
// CSARM_LOAD_DONE.  Interpose the three process-exit entry points (exit,
// _exit, pthread_exit) in libtier0 (first Valve lib loaded by BOTH test
// activities, DT_NEEDED of every port lib — bionic resolves the caller's UND
// through its own DT_NEEDED closure BEFORE the global group, so ours wins).
//
// Backtrace via _Unwind_Backtrace + dladdr — bionic libc.so does NOT export
// backtrace() at API 30 (run 41206898100: libtier0 dlopen failed with
// 'cannot locate symbol backtrace'), while _Unwind_* resolve everywhere
// (C++ exception plumbing already depends on them) and dladdr is API 21+.
#include <dlfcn.h>
#include <unistd.h>
#include <unwind.h>
#include <android/log.h>

typedef void (*exit_fn_t)(int);
typedef void (*pthread_exit_fn_t)(void *);

struct BtCtx
{
	void **frames;
	int max;
	int n;
};

static _Unwind_Reason_Code bt_cb( struct _Unwind_Context *ctx, void *data )
{
	BtCtx *c = (BtCtx *)data;
	if ( c->n >= c->max )
		return _URC_END_OF_STACK;
	c->frames[ c->n++ ] = (void *)_Unwind_GetIP( ctx );
	return _URC_NO_REASON;
}

static void csarm_log_exit( const char *what, long code )
{
	void *bt[48];
	BtCtx ctx = { bt, 48, 0 };
	_Unwind_Backtrace( bt_cb, &ctx );
	__android_log_print( ANDROID_LOG_ERROR, "CSARM",
		"CSARM_EXIT_HIT %s code=%ld depth=%d", what, code, ctx.n );
	for ( int i = 0; i < ctx.n; i++ )
	{
		Dl_info info;
		if ( dladdr( bt[i], &info ) && info.dli_fname )
			__android_log_print( ANDROID_LOG_ERROR, "CSARM",
				"CSARM_EXIT_BT %02d %s+%lx", i, info.dli_fname,
				(unsigned long)( (char *)bt[i] - (char *)info.dli_fbase ) );
		else
			__android_log_print( ANDROID_LOG_ERROR, "CSARM",
				"CSARM_EXIT_BT %02d %p", i, bt[i] );
	}
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
	for ( ;; ) __asm__ volatile( "" );
}

extern "C" __attribute__((noreturn)) void pthread_exit( void *retval )
{
	csarm_log_exit( "pthread_exit", (long)(intptr_t)retval );
	volatile pthread_exit_fn_t real =
		(pthread_exit_fn_t)dlsym( RTLD_NEXT, "pthread_exit" );
	if ( real )
		real( retval );
	_exit( 0 );
}
