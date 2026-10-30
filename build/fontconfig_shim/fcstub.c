/* csARM — fontconfig stub implementations (see fontconfig/fontconfig.h).
 * Everything reports "no fonts available"; nothing crashes. */
#include <fontconfig/fontconfig.h>
#include <stdlib.h>

FcConfig *FcInitLoadConfigAndFonts(void) { return NULL; }
FcBool FcInit(void) { return FcFalse; }
FcConfig *FcConfigGetCurrent(void) { return NULL; }
FcBool FcConfigAppFontAddDir(FcConfig *config, const FcChar8 *dir)
{ (void)config; (void)dir; return FcFalse; }
FcBool FcConfigSubstitute(FcConfig *config, FcPattern *p, FcMatchKind kind)
{ (void)config; (void)p; (void)kind; return FcFalse; }
void FcDefaultSubstitute(FcPattern *pattern) { (void)pattern; }

FcPattern *FcPatternCreate(void) { return NULL; }
void FcPatternDestroy(FcPattern *p) { (void)p; }
FcBool FcPatternAdd(FcPattern *p, const char *object, FcValue value, FcBool append)
{ (void)p; (void)object; (void)value; (void)append; return FcFalse; }
FcResult FcPatternGetString(FcPattern *p, const char *object, int n, FcChar8 **s)
{ (void)p; (void)object; (void)n; (void)s; return FcResultNoMatch; }
FcResult FcPatternGetBool(FcPattern *p, const char *object, int n, FcBool *b)
{ (void)p; (void)object; (void)n; (void)b; return FcResultNoMatch; }

FcPattern *FcFontMatch(FcConfig *config, FcPattern *p, FcResult *result)
{ (void)config; (void)p; if (result) *result = FcResultNoMatch; return NULL; }
FcFontSet *FcFontList(FcConfig *config, FcPattern *p, FcObjectSet *os)
{ (void)config; (void)p; (void)os; return NULL; }
void FcFontSetDestroy(FcFontSet *fs)
{ if (fs) free(fs); }

FcObjectSet *FcObjectSetCreate(void) { return NULL; }
FcBool FcObjectSetAdd(FcObjectSet *os, const char *object)
{ (void)os; (void)object; return FcFalse; }
void FcObjectSetDestroy(FcObjectSet *os) { (void)os; }
