// csARM — aarch64 math unit tests (runs under qemu-aarch64 in CI)
// Validates the ARM/NEON mathlib paths ported from SSE.
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "tier0/platform.h"
#include "mathlib/mathlib.h"
#include "mathlib/vector.h"
#include "mathlib/vmatrix.h"

static int g_fail = 0;

#define CHECK_CLOSE(expr, expected, eps)                                                          \
	do                                                                                           \
	{                                                                                            \
		double _v = (double)(expr);                                                              \
		double _e = (double)(expected);                                                          \
		if ( fabs( _v - _e ) > (eps) )                                                           \
		{                                                                                        \
			printf( "FAIL %s:%d: %s = %.9f expected %.9f (eps %.9f)\n", __FILE__, __LINE__,      \
					#expr, _v, _e, (eps) );                                                      \
			g_fail++;                                                                            \
		}                                                                                        \
		else                                                                                     \
		{                                                                                        \
			printf( "ok   %s = %.9f\n", #expr, _v );                                             \
		}                                                                                        \
	} while ( 0 )

static bool VectorsEqual( const Vector &a, const Vector &b, float eps )
{
	return fabs( a.x - b.x ) < eps && fabs( a.y - b.y ) < eps && fabs( a.z - b.z ) < eps;
}

int main( int argc, char *argv[] )
{
	MathLib_Init( 2.2f, 2.2f, 0.0f, 2.2f, false, false, false, false );

	printf( "=== csARM math tests (aarch64) ===\n" );

	// --- VectorNormalize (NEON path) ---
	{
		Vector v( 3.0f, 4.0f, 0.0f );
		float len = VectorNormalize( v );
		CHECK_CLOSE( len, 5.0, 1e-5 );
		CHECK_CLOSE( v.x, 0.6, 1e-5 );
		CHECK_CLOSE( v.y, 0.8, 1e-5 );
		CHECK_CLOSE( v.z, 0.0, 1e-6 );
	}
	{
		Vector v( 1.0f, 1.0f, 1.0f );
		VectorNormalize( v );
		CHECK_CLOSE( v.Length(), 1.0, 1e-5 );
	}
	{
		// zero vector must not produce NaN
		Vector v( 0.0f, 0.0f, 0.0f );
		VectorNormalize( v );
		CHECK_CLOSE( v.x + v.y + v.z, 0.0, 1e-9 );
	}

	// --- trig (FastSinCos / ARM branch) ---
	{
		float s, c;
		FastSinCos( 0.0f, &s, &c );
		CHECK_CLOSE( s, 0.0, 1e-4 );
		CHECK_CLOSE( c, 1.0, 1e-4 );
		FastSinCos( M_PI_F / 2, &s, &c );
		CHECK_CLOSE( s, 1.0, 1e-4 );
		CHECK_CLOSE( c, 0.0, 1e-4 );
		FastSinCos( M_PI_F / 6, &s, &c );
		CHECK_CLOSE( s, 0.5, 1e-4 );
	}
	{
		CHECK_CLOSE( FastCos( 0.0f ), 1.0, 1e-4 );
		CHECK_CLOSE( FastCos( M_PI_F ), -1.0, 1e-4 );
		CHECK_CLOSE( FastSin( M_PI_F / 2 ), 1.0, 1e-4 );
	}

	// --- dot/cross products ---
	{
		Vector a( 1, 2, 3 ), b( 4, 5, 6 );
		CHECK_CLOSE( DotProduct( a, b ), 32.0, 1e-6 );
		Vector c = a.Cross( b );
		bool ok = VectorsEqual( c, Vector( -3, 6, -3 ), 1e-6 );
		if ( !ok ) { printf( "FAIL cross product\n" ); g_fail++; } else printf( "ok   cross\n" );
	}

	// --- AngleVectors / VectorAngles roundtrip ---
	{
		QAngle angles( 10.0f, 20.0f, 0.0f );
		Vector fwd, right, up;
		AngleVectors( angles, &fwd, &right, &up );
		CHECK_CLOSE( fwd.Length(), 1.0, 1e-4 );
		CHECK_CLOSE( right.Length(), 1.0, 1e-4 );
		CHECK_CLOSE( up.Length(), 1.0, 1e-4 );
		CHECK_CLOSE( fabs( DotProduct( fwd, right ) ), 0.0, 1e-3 );
		CHECK_CLOSE( fabs( DotProduct( fwd, up ) ), 0.0, 1e-3 );

		QAngle back;
		VectorAngles( fwd, back );
		// pitch/yaw should match (roll is 0 from VectorAngles)
		CHECK_CLOSE( back.x, 10.0, 1e-2 );
		CHECK_CLOSE( back.y, 20.0, 1e-2 );
	}

	// --- quaternion ---
	{
		QAngle angles( 30.0f, 45.0f, 60.0f );
		Quaternion q;
		AngleQuaternion( angles, q );
		QAngle out;
		QuaternionAngles( q, out );
		CHECK_CLOSE( out.x, 30.0, 1e-2 );
		CHECK_CLOSE( out.y, 45.0, 1e-2 );
		CHECK_CLOSE( out.z, 60.0, 1e-2 );
	}

	// --- matrix transform ---
	{
		VMatrix m;  // identity
		m.Identity();
		Vector p( 1, 2, 3 );
		Vector r = m * p;
		bool ok = VectorsEqual( r, p, 1e-6 );
		if ( !ok ) { printf( "FAIL identity transform\n" ); g_fail++; } else printf( "ok   identity transform\n" );

		VMatrix t;  // translation by (10,0,0)
		t.Identity();
		t[0][3] = 10.0f;
		Vector r2 = t * p;
		bool ok2 = VectorsEqual( r2, Vector( 11, 2, 3 ), 1e-6 );
		if ( !ok2 ) { printf( "FAIL translation transform\n" ); g_fail++; } else printf( "ok   translation transform\n" );
	}

	// --- FloatBits / bit tricks ---
	{
		CHECK_CLOSE( FloatBits( 1.0f ) & 0x7fffffff, 0x3f800000, 0 );
	}

	// --- ssemath SIMD sanity: FourVectors normalize ---
	{
		FourVectors fv;
		fv.DuplicateVector( Vector( 3.0f, 4.0f, 0.0f ) );
		fv.VectorNormalize();
		float x = fv.X( 0 ), y = fv.Y( 0 );
		CHECK_CLOSE( x, 0.6, 1e-4 );
		CHECK_CLOSE( y, 0.8, 1e-4 );
	}

	printf( "=== %s: %d failures ===\n", g_fail == 0 ? "ALL PASSED" : "FAILED", g_fail );
	return g_fail == 0 ? 0 : 1;
}
