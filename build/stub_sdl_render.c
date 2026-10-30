/* csARM — SDL renderer API stubs.
 *
 * SDL 2.0.2's SDL_video.c implements SDL_CreateWindowFramebuffer on top of
 * the renderer API, so libSDL2 references SDL_CreateRenderer /
 * SDL_RenderCopy / ... even though we exclude src/render/* from the build
 * (the CS:GO engine renders through ToGL and never calls SDL_Render*).
 * Leaving them UND would make bionic dlopen fail on libSDL2.so.
 *
 * These stubs keep the symbols alive and return errors, exactly like a
 * build with SDL_RENDER_DISABLED would behave.
 */
#include "SDL_render.h"
#include "SDL_video.h"
#include "SDL_error.h"

#ifdef __cplusplus
extern "C" {
#endif

SDL_Renderer *SDL_CreateRenderer(SDL_Window *window, int index, Uint32 flags)
{ (void)window; (void)index; (void)flags; SDL_SetError("SDL renderer disabled (csARM)"); return NULL; }

SDL_Texture *SDL_CreateTexture(SDL_Renderer *renderer, Uint32 format, int access, int w, int h)
{ (void)renderer; (void)format; (void)access; (void)w; (void)h;
  SDL_SetError("SDL renderer disabled (csARM)"); return NULL; }

void SDL_DestroyRenderer(SDL_Renderer *renderer) { (void)renderer; }
void SDL_DestroyTexture(SDL_Texture *texture) { (void)texture; }

int SDL_GetNumRenderDrivers(void) { return 0; }

int SDL_GetRenderDriverInfo(int index, SDL_RendererInfo *info)
{ (void)index; (void)info; return -1; }

int SDL_GetRendererInfo(SDL_Renderer *renderer, SDL_RendererInfo *info)
{ (void)renderer; (void)info; return -1; }

int SDL_RenderCopy(SDL_Renderer *renderer, SDL_Texture *texture,
                   const SDL_Rect *srcrect, const SDL_Rect *dstrect)
{ (void)renderer; (void)texture; (void)srcrect; (void)dstrect; return -1; }

void SDL_RenderPresent(SDL_Renderer *renderer) { (void)renderer; }

int SDL_RenderSetViewport(SDL_Renderer *renderer, const SDL_Rect *rect)
{ (void)renderer; (void)rect; return -1; }

int SDL_UpdateTexture(SDL_Texture *texture, const SDL_Rect *rect,
                      const void *pixels, int pitch)
{ (void)texture; (void)rect; (void)pixels; (void)pitch; return -1; }

#ifdef __cplusplus
}
#endif
