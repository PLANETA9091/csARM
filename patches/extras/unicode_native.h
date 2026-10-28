// csARM — native unicode conversion for Android bionic (no iconv)
// Conventions mirror the original iconv-based return values.
#ifndef TIER1_UNICODE_NATIVE_H
#define TIER1_UNICODE_NATIVE_H
#ifdef ANDROID

#include "tier0/platform.h"
#include <wchar.h>
#include <string.h>

// UCS-2 (2-byte, BMP) -> wchar_t (4-byte UTF-32 on Android). Returns bytes written to pUnicode.
inline int V_NativeUCS2ToUnicode( const ucs2 *pUCS2, wchar_t *pUnicode, int cubDestSizeInBytes )
{
	if ( !pUCS2 || !pUnicode || cubDestSizeInBytes < (int)sizeof(wchar_t) )
		return 0;
	int maxChars = cubDestSizeInBytes / sizeof(wchar_t) - 1; // leave room for terminator
	int n = 0;
	const ucs2 *pSrc = pUCS2;
	while ( n < maxChars && pSrc[n] != 0 )
	{
		pUnicode[n] = (wchar_t)pSrc[n]; // UCS-2 unit == UTF-32 code point (BMP)
		n++;
	}
	pUnicode[n] = 0;
	return n * (int)sizeof(wchar_t);
}

// wchar_t (UTF-32) -> UCS-2. Returns number of source characters converted.
inline int V_NativeUnicodeToUCS2( const wchar_t *pUnicode, int cubSrcInBytes, void *pUCS2Buf, int cubDestSizeInBytes )
{
	if ( !pUnicode || !pUCS2Buf || cubDestSizeInBytes < (int)sizeof(ucs2) )
		return 0;
	ucs2 *pUCS2 = (ucs2 *)pUCS2Buf;
	int maxChars = cubDestSizeInBytes / (int)sizeof(ucs2) - 1;
	int srcChars = cubSrcInBytes / (int)sizeof(wchar_t);
	int n = 0;
	while ( n < maxChars && n < srcChars && pUnicode[n] != 0 )
	{
		wchar_t wc = pUnicode[n];
		pUCS2[n] = (wc > 0xFFFF) ? (ucs2)'?' : (ucs2)wc; // BMP clamp like UCS-2
		n++;
	}
	pUCS2[n] = 0;
	return n;
}

// UCS-2 -> UTF-8. Returns bytes written (matches iconv 'remaining' convention).
inline int V_NativeUCS2ToUTF8( const ucs2 *pUCS2, char *pUTF8, int cubDestSizeInBytes )
{
	if ( !pUCS2 || !pUTF8 || cubDestSizeInBytes < 1 )
		return 0;
	int out = 0, max = cubDestSizeInBytes - 1;
	for ( const ucs2 *p = pUCS2; *p && out < max; p++ )
	{
		unsigned int c = *p;
		if ( c < 0x80 )
			pUTF8[out++] = (char)c;
		else if ( c < 0x800 && out + 1 < cubDestSizeInBytes )
		{
			pUTF8[out++] = (char)(0xC0 | (c >> 6));
			pUTF8[out++] = (char)(0x80 | (c & 0x3F));
		}
		else if ( out + 2 < cubDestSizeInBytes )
		{
			pUTF8[out++] = (char)(0xE0 | (c >> 12));
			pUTF8[out++] = (char)(0x80 | ((c >> 6) & 0x3F));
			pUTF8[out++] = (char)(0x80 | (c & 0x3F));
		}
		else break;
	}
	pUTF8[out] = 0;
	return out;
}

// UTF-8 -> UCS-2. Returns source bytes consumed (matches original convention).
inline int V_NativeUTF8ToUCS2( const char *pUTF8, int cubSrcInBytes, void *pUCS2Buf, int cubDestSizeInBytes )
{
	if ( !pUTF8 || !pUCS2Buf || cubDestSizeInBytes < (int)sizeof(ucs2) )
		return 0;
	ucs2 *pUCS2 = (ucs2 *)pUCS2Buf;
	int maxChars = cubDestSizeInBytes / (int)sizeof(ucs2) - 1;
	int n = 0, i = 0;
	while ( i < cubSrcInBytes && n < maxChars && pUTF8[i] != 0 )
	{
		unsigned char b = (unsigned char)pUTF8[i];
		unsigned int cp;
		int adv;
		if ( b < 0x80 )      { cp = b; adv = 1; }
		else if ( (b & 0xE0) == 0xC0 ) { cp = b & 0x1F; adv = 2; }
		else if ( (b & 0xF0) == 0xE0 ) { cp = b & 0x0F; adv = 3; }
		else if ( (b & 0xF8) == 0xF0 ) { cp = b & 0x07; adv = 4; }
		else { cp = '?'; adv = 1; }
		if ( i + adv > cubSrcInBytes ) break;
		for ( int k = 1; k < adv; k++ )
		{
			unsigned char cb = (unsigned char)pUTF8[i + k];
			if ( (cb & 0xC0) != 0x80 ) { cp = '?'; adv = 1; break; }
			cp = (cp << 6) | (cb & 0x3F);
		}
		if ( cp > 0xFFFF )
			pUCS2[n] = (ucs2)'?';
		else
			pUCS2[n] = (ucs2)cp;
		n++;
		i += adv;
	}
	pUCS2[n] = 0;
	return i;
}

#endif // ANDROID
#endif // TIER1_UNICODE_NATIVE_H
