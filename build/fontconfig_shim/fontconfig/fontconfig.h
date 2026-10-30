/* csARM — minimal fontconfig shim (headers only) for Android.
 *
 * Valve's vgui2/vgui_surfacelib/linuxfont.cpp enumerates system fonts via
 * fontconfig.  Android has no fontconfig (the system font stack is
 * framework-internal), so we ship an API-compatible stub: the functions
 * exist (build/fontconfig_shim/fcstub.c), but no fonts are ever returned,
 * leaving the engine UI with bitmap/default fonts only.  Text rendering via
 * FreeType still works for fonts registered directly (CreateFromMemory).
 */
#ifndef CSARM_FONTCONFIG_SHIM_H
#define CSARM_FONTCONFIG_SHIM_H

#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int FcBool;
/* real fontconfig uses unsigned char; the Valve call sites pass plain
 * string literals, so C++ builds need char to avoid const-mismatch errors */
#ifdef __cplusplus
typedef char FcChar8;
#else
typedef unsigned char FcChar8;
#endif

#define FcTrue  1
#define FcFalse 0

typedef enum _FcType {
    FcTypeVoid = 0,
    FcTypeInteger,
    FcTypeDouble,
    FcTypeString,
    FcTypeBool,
    FcTypeMatrix,
    FcTypeCharSet,
    FcTypeFTFace,
    FcTypeLangSet
} FcType;

typedef struct _FcValue {
    FcType type;
    union {
        const FcChar8 *s;
        int i;
        FcBool b;
        double d;
        const void *f;
        const void *p;
    } u;
} FcValue;

typedef enum _FcResult {
    FcResultMatch, FcResultNoMatch, FcResultTypeMismatch, FcResultNoId,
    FcResultOutOfMemory
} FcResult;

typedef enum _FcMatchKind { FcMatchPattern, FcMatchFont, FcMatchScan } FcMatchKind;

typedef struct _FcConfig FcConfig;
typedef struct _FcPattern FcPattern;
typedef struct _FcObjectSet FcObjectSet;
typedef struct _FcFontSet FcFontSet;

struct _FcFontSet {
    int nfont;
    int sfont;
    FcPattern **fonts;
};

/* FC property constants (string ones are macros in real fontconfig, weight
 * / slant are numeric constants passed through varargs as int) */
#define FC_FAMILY       "family"
#define FC_STYLE        "style"
#define FC_SLANT        "slant"
#define FC_WEIGHT       "weight"
#define FC_SIZE         "size"
#define FC_FILE         "file"
#define FC_SCALABLE     "scalable"
#define FC_FULLNAME     "fullname"
#define FC_FAMILYLANG   "familylang"

#define FC_WEIGHT_NORMAL    80
#define FC_WEIGHT_BOLD      200
#define FC_SLANT_ROMAN      0
#define FC_SLANT_ITALIC     100

/* stub library (fcstub.c) */
FcConfig  *FcInitLoadConfigAndFonts(void);
FcBool     FcInit(void);
FcConfig  *FcConfigGetCurrent(void);
FcBool     FcConfigAppFontAddDir(FcConfig *config, const FcChar8 *dir);
FcBool     FcConfigSubstitute(FcConfig *config, FcPattern *p, FcMatchKind kind);
void       FcDefaultSubstitute(FcPattern *pattern);
FcPattern *FcPatternCreate(void);
void       FcPatternDestroy(FcPattern *p);
FcBool     FcPatternAdd(FcPattern *p, const char *object, FcValue value, FcBool append);
FcResult   FcPatternGetString(FcPattern *p, const char *object, int n, FcChar8 **s);
FcResult   FcPatternGetBool(FcPattern *p, const char *object, int n, FcBool *b);
FcPattern *FcFontMatch(FcConfig *config, FcPattern *p, FcResult *result);
FcFontSet *FcFontList(FcConfig *config, FcPattern *p, FcObjectSet *os);
void       FcFontSetDestroy(FcFontSet *fs);
FcObjectSet *FcObjectSetCreate(void);
FcBool     FcObjectSetAdd(FcObjectSet *os, const char *object);
void       FcObjectSetDestroy(FcObjectSet *os);

#ifdef __cplusplus
}
#endif

#endif /* CSARM_FONTCONFIG_SHIM_H */
