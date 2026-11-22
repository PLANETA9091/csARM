/*
 * csARM — regression test for the gl4es framebuffer-deletion crash.
 *
 * The engine (shaderapidx9 -> ToGL) deletes a render-target FBO while it is
 * still the tracked current framebuffer (CTexture::ReconstructTexture frees
 * and reallocates the texture).  Upstream gl4es set
 * glstate->fbo.current_fb = 0 on delete, and the next
 * IDirect3DDevice9::SetViewport -> glViewport dereferenced that NULL:
 *
 *   #00 libGL.so              glViewport+35            (cmpl $0,(%rax), rax=0)
 *   #01 libtogl.so            IDirect3DDevice9::SetViewport
 *   #02 libshaderapidx9.so    CommitSetViewports
 *   #03 libshaderapidx9.so    CShaderAPIDx8::ClearBuffers
 *   #04 libmaterialsystem.so  CTexture::ReconstructTexture
 *
 * patches/gl4es/0001-fbo-delete-rebind-default.patch restores the default
 * framebuffer instead.  This test reproduces exactly that sequence on a
 * real EGL/GLES stack (gl4es over SwiftShader on device, gl4es over the host
 * driver on desktop) and must exit 0.
 *
 * build: test/build_gl4es_test.sh   (cross-compiles for the device)
 * run:   adb shell /data/local/tmp/gltest/gl4es_fbo_delete
 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef void GLvoid;

#define EGL_OPENGL_ES2_BIT 0x0004
#define EGL_SURFACE_TYPE 0x3033
#define EGL_PBUFFER_BIT 0x0001
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_NONE 0x3038
#define EGL_WIDTH 0x3057
#define EGL_HEIGHT 0x3056
#define EGL_CONTEXT_CLIENT_VERSION 0x3098

#define GL_FRAMEBUFFER 0x8D40
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_RGBA8 0x8058
#define GL_TEXTURE_2D 0x0DE1
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5

static void *H(const char *path) {
	void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
	if (!h) { fprintf(stderr, "dlopen %s: %s\n", path, dlerror()); exit(2); }
	return h;
}
static void *S(void *h, const char *name) {
	void *p = dlsym(h, name);
	if (!p) { fprintf(stderr, "dlsym %s: %s\n", name, dlerror()); exit(2); }
	return p;
}

int main(int argc, char **argv) {
	const char *dir = (argc > 1) ? argv[1] : ".";
	char path[1024];

	/* gl4es: libEGLgl4es.so wraps EGL and creates the GL context through its
	 * own loader; libGL.so is the desktop-GL entry point the engine uses. */
	/* Load the desktop-GL library FIRST: its SONAME is libGL.so.1 and the
	 * gl4es EGL wrapper has that as DT_NEEDED.  bionic resolves a NEEDED
	 * entry against an already-loaded soname, while it does NOT honour
	 * LD_LIBRARY_PATH/rpath for the "default" namespace of a shell binary. */
	snprintf(path, sizeof path, "%s/libGL.so", dir);
	void *glH = H(path);
	snprintf(path, sizeof path, "%s/libEGLgl4es.so", dir);
	void *eglH = H(path);

	void *(*eglGetDisplay)(void *) = (void *(*)(void *))S(eglH, "eglGetDisplay");
	unsigned (*eglInitialize)(void *, int *, int *) = (unsigned (*)(void *, int *, int *))S(eglH, "eglInitialize");
	unsigned (*eglChooseConfig)(void *, const int *, void **, int, int *) = (unsigned (*)(void *, const int *, void **, int, int *))S(eglH, "eglChooseConfig");
	void *(*eglCreatePbufferSurface)(void *, void *, const int *) = (void *(*)(void *, void *, const int *))S(eglH, "eglCreatePbufferSurface");
	void *(*eglCreateContext)(void *, void *, void *, const int *) = (void *(*)(void *, void *, void *, const int *))S(eglH, "eglCreateContext");
	unsigned (*eglMakeCurrent)(void *, void *, void *, void *) = (unsigned (*)(void *, void *, void *, void *))S(eglH, "eglMakeCurrent");
	const char *(*eglQueryString)(void *, int) = (const char *(*)(void *, int))S(eglH, "eglQueryString");

	typedef void (*PFNGENF)(int, GLuint *);
	typedef void (*PFNBINDF)(GLenum, GLuint);
	typedef void (*PFNDELF)(int, const GLuint *);
	typedef void (*PFNVIEWPORT)(GLint, GLint, GLsizei, GLsizei);
	PFNGENF glGenFramebuffers = (PFNGENF)S(glH, "glGenFramebuffers");
	PFNBINDF glBindFramebuffer = (PFNBINDF)S(glH, "glBindFramebuffer");
	PFNDELF glDeleteFramebuffers = (PFNDELF)S(glH, "glDeleteFramebuffers");
	PFNVIEWPORT glViewport = (PFNVIEWPORT)S(glH, "glViewport");

	void *dpy = eglGetDisplay((void *)0);
	int major = 0, minor = 0;
	if (!eglInitialize(dpy, &major, &minor)) { fprintf(stderr, "eglInitialize failed\n"); return 2; }
	printf("EGL %d.%d vendor=%s\n", major, minor, eglQueryString(dpy, 0x3053));

	int cfgAttr[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE };
	void *cfg = NULL; int ncfg = 0;
	if (!eglChooseConfig(dpy, cfgAttr, &cfg, 1, &ncfg) || !cfg) { fprintf(stderr, "eglChooseConfig failed\n"); return 2; }
	int pbAttr[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE };
	void *surf = eglCreatePbufferSurface(dpy, cfg, pbAttr);
	int ctxAttr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	void *ctx = eglCreateContext(dpy, cfg, (void *)0, ctxAttr);
	if (!surf || !ctx) { fprintf(stderr, "surface/context creation failed\n"); return 2; }
	if (!eglMakeCurrent(dpy, surf, surf, ctx)) { fprintf(stderr, "eglMakeCurrent failed\n"); return 2; }
	puts("context current");

	/* The engine's render-target path: one FBO is bound, then destroyed while
	 * bound (texture realloc), then the next ClearBuffers commits the viewport. */
	GLuint fbo = 0;
	glGenFramebuffers(1, &fbo);
	printf("FBO %u generated\n", fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glViewport(0, 0, 64, 64);          /* healthy call, tracked current_fb = fbo */
	glDeleteFramebuffers(1, &fbo);     /* deletes the BOUND framebuffer */
	printf("bound FBO deleted\n");
	fflush(stdout);

	glViewport(0, 0, 64, 64);          /* <- SIGSEGV before the csARM patch */
	puts("PASS: glViewport after deleting the bound FBO");
	return 0;
}
