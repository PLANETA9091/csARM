/* Does gl4es' glBlitFramebufferEXT actually move pixels to the default
 * framebuffer?  ToGL's present path is exactly this blit; a black screen with
 * a correctly rendered world means it is a no-op. */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned int GLenum; typedef unsigned int GLuint; typedef int GLint;
#define EGL_NONE 0x3038
#define EGL_WIDTH 0x3057
#define EGL_HEIGHT 0x3056
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define EGL_SURFACE_TYPE 0x3033
#define EGL_PBUFFER_BIT 0x0001
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_OPENGL_ES2_BIT 0x0004
#define GL_TEXTURE_2D 0x0DE1
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
#define GL_FRAMEBUFFER 0x8D40
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_READ_FRAMEBUFFER 0x8CA8
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#define GL_COLOR_BUFFER_BIT 0x4000
#define GL_NEAREST 0x2600
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_CLAMP_TO_EDGE 0x812F
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
static void *H(const char *p){void*h=dlopen(p,RTLD_NOW|RTLD_GLOBAL);if(!h){fprintf(stderr,"dlopen %s: %s\n",p,dlerror());exit(2);}return h;}
static void *S(void *h,const char *n){void*p=dlsym(h,n);if(!p){fprintf(stderr,"dlsym %s\n",n);exit(2);}return p;}
int main(int argc,char**argv){
	const char *dir=argc>1?argv[1]:"."; char path[1024];
	snprintf(path,sizeof path,"%s/libGL.so",dir); void*glH=H(path);
	snprintf(path,sizeof path,"%s/libEGLgl4es.so",dir); void*eglH=H(path);
	void*(*eglGetDisplay)(void*)=(void*(*)(void*))S(eglH,"eglGetDisplay");
	unsigned(*eglInitialize)(void*,int*,int*)=(unsigned(*)(void*,int*,int*))S(eglH,"eglInitialize");
	unsigned(*eglChooseConfig)(void*,const int*,void**,int,int*)=(unsigned(*)(void*,const int*,void**,int,int*))S(eglH,"eglChooseConfig");
	void*(*eglCreatePbufferSurface)(void*,void*,const int*)=(void*(*)(void*,void*,const int*))S(eglH,"eglCreatePbufferSurface");
	void*(*eglCreateContext)(void*,void*,void*,const int*)=(void*(*)(void*,void*,void*,const int*))S(eglH,"eglCreateContext");
	unsigned(*eglMakeCurrent)(void*,void*,void*,void*)=(unsigned(*)(void*,void*,void*,void*))S(eglH,"eglMakeCurrent");
	void(*glGenTextures)(int,GLuint*)=(void(*)(int,GLuint*))S(glH,"glGenTextures");
	void(*glBindTexture)(GLenum,GLuint)=(void(*)(GLenum,GLuint))S(glH,"glBindTexture");
	void(*glTexImage2D)(GLenum,int,int,int,int,int,GLenum,GLenum,const void*)=(void(*)(GLenum,int,int,int,int,int,GLenum,GLenum,const void*))S(glH,"glTexImage2D");
	void(*glTexParameteri)(GLenum,GLenum,int)=(void(*)(GLenum,GLenum,int))S(glH,"glTexParameteri");
	void(*glGenFramebuffers)(int,GLuint*)=(void(*)(int,GLuint*))S(glH,"glGenFramebuffers");
	void(*glBindFramebuffer)(GLenum,GLuint)=(void(*)(GLenum,GLuint))S(glH,"glBindFramebuffer");
	void(*glFramebufferTexture2D)(GLenum,GLenum,GLenum,GLuint,int)=(void(*)(GLenum,GLenum,GLenum,GLuint,int))S(glH,"glFramebufferTexture2D");
	void(*glBlitFramebuffer)(GLint,GLint,GLint,GLint,GLint,GLint,GLint,GLint,GLenum,GLenum)=(void(*)(GLint,GLint,GLint,GLint,GLint,GLint,GLint,GLint,GLenum,GLenum))S(glH,"glBlitFramebuffer");
	void(*glReadPixels)(int,int,int,int,GLenum,GLenum,void*)=(void(*)(int,int,int,int,GLenum,GLenum,void*))S(glH,"glReadPixels");
	void(*glClearColor)(float,float,float,float)=(void(*)(float,float,float,float))S(glH,"glClearColor");
	void(*glClear)(GLuint)=(void(*)(GLuint))S(glH,"glClear");
	void(*glViewport)(int,int,int,int)=(void(*)(int,int,int,int))S(glH,"glViewport");

	void*dpy=eglGetDisplay(0); int ma=0,mi=0; if(!eglInitialize(dpy,&ma,&mi)){puts("eglInitialize failed");return 2;}
	int cfgAttr[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES2_BIT,EGL_NONE};
	void*cfg=0;int n=0; if(!eglChooseConfig(dpy,cfgAttr,&cfg,1,&n)||!cfg){puts("cfg failed");return 2;}
	int pb[]={EGL_WIDTH,256,EGL_HEIGHT,256,EGL_NONE};
	void*surf=eglCreatePbufferSurface(dpy,cfg,pb);
	int ca[]={EGL_CONTEXT_CLIENT_VERSION,2,EGL_NONE};
	void*ctx=eglCreateContext(dpy,cfg,0,ca);
	if(!surf||!ctx||!eglMakeCurrent(dpy,surf,surf,ctx)){puts("ctx failed");return 2;}
	glViewport(0,0,256,256);
	glClearColor(0,0,0,1); glClear(GL_COLOR_BUFFER_BIT);

	GLuint tex=0; glGenTextures(1,&tex); glBindTexture(GL_TEXTURE_2D,tex);
	unsigned char red[64*64*4]; for(int i=0;i<64*64;i++){red[i*4+0]=255;red[i*4+1]=0;red[i*4+2]=0;red[i*4+3]=255;}
	glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,64,64,0,GL_RGBA,GL_UNSIGNED_BYTE,red);
	glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
	GLuint fbo=0; glGenFramebuffers(1,&fbo);
	glBindFramebuffer(GL_FRAMEBUFFER,fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0);
	glBindFramebuffer(GL_READ_FRAMEBUFFER,fbo);
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER,0);
	glBlitFramebuffer(0,0,64,64, 0,0,64,64, GL_COLOR_BUFFER_BIT, GL_NEAREST);
	glBindFramebuffer(GL_FRAMEBUFFER,0);
	unsigned char px[4]={0,0,0,0};
	glReadPixels(8,8,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
	printf("blit result pixel = %d,%d,%d,%d -> %s\n",px[0],px[1],px[2],px[3],
		(px[0]>200&&px[1]<60&&px[2]<60)?"PASS (blit works)":"FAIL (no pixels moved)");
	return (px[0]>200&&px[1]<60&&px[2]<60)?0:1;
}
