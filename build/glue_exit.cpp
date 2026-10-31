// csARM — exit() interposer for boot diagnosis.
//
// Run 41198597552: libclient.so now dlopen's clean (all relocations resolve)
// and its static initializers run for the first time — one of them ends the
// process with a clean exit(0) before CSARM_LOAD_DONE ever prints.  An
// interposed exit() in libtier0 (the first Valve lib loaded by BOTH test
// activities, and a DT_NEEDED of every port lib) turns the silent exit into
// a logcat backtrace: CSARM_EXIT_HIT + CSARM_EXIT_BT lines land in the CI
// artifact and name the caller.  The real exit is reached via RTLD_NEXT.
#include <dlfcn.h>
#include <unistd.h>
#include <android/log.h>
#include <execinfo.h>

typedef void (*real_exit_t)(int) __attribute__((noreturn));

extern "C" __attribute__((noreturn)) void exit(int code)
{
	// backtrace BEFORE logging anything else — frames are still intact
	void *bt[48];
	int n = backtrace(bt, 48);
	__android_log_print(ANDROID_LOG_ERROR, "CSARM",
		"CSARM_EXIT_HIT code=%d depth=%d", code, n);
	for (int i = 0; i < n; i++)
		__android_log_print(ANDROID_LOG_ERROR, "CSARM",
			"CSARM_EXIT_BT %02d %p", i, bt[i]);

	volatile real_exit_t real =
		(real_exit_t)dlsym( RTLD_NEXT, "exit" );
	if ( real )
		real( code );
	// RTLD_NEXT failed (should not happen) — fall back to _exit
	__android_log_print(ANDROID_LOG_ERROR, "CSARM", "CSARM_EXIT_NO_REAL");
	_exit( code );
}
