package com.csarm.port;

import android.app.Activity;
import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.widget.FrameLayout;
import android.widget.TextView;

import java.util.ArrayList;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * csARM visual test.
 * 1) Loads every ported library in dependency order (bionic dlopen resolves
 *    DT_NEEDED chains; UnsatisfiedLinkError = real ABI/symbol problem).
 * 2) Renders an animated GLES2 scene (gradient + rotating triangle driven by
 *    time) so the workflow can screencap visual proof on an ARM64 stack.
 * Status is reported via logcat lines: CSARM_LIB_OK / CSARM_LIB_FAIL /
 * CSARM_LOAD_DONE / CSARM_FRAME.
 */
public class MainActivity extends Activity implements GLSurfaceView.Renderer {
    static final String TAG = "CSARM";

    static final String[] LIBS = {
        "c++_shared",
        "protobuf", "tier0", "tier1", "tier2", "vstdlib", "mathlib",
        "appframework", "datacache", "studiorender", "soundemittersystem",
        "vguimatsurface", "vgui", "vgui_controls", "materialsystem",
        "engine", "client", "server"
    };

    // game DLLs are content-path: the engine loads them at map load, not at
    // boot.  A missing content symbol must NOT abort the load loop — the
    // failure is tagged CSARM_LIB_FAIL_CONTENT and CI treats it as a warning
    // until the content stack (particles lib, GCSDK, vphysics) is fully ported.
    static boolean isContentLib(String lib) {
        return lib.equals("client") || lib.equals("server");
    }

    static int loadErrors = 0;
    static int loadOk = 0;
    static int frames = 0;
    GLSurfaceView glView;
    TextView status;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        StringBuilder report = new StringBuilder();
        for (String lib : LIBS) {
            try {
                System.loadLibrary(lib);
                loadOk++;
                Log.i(TAG, "CSARM_LIB_OK " + lib);
                report.append(lib).append(" OK\n");
            } catch (Throwable e) {
                loadErrors++;
                String msg = e.getMessage() == null ? e.toString() : e.getMessage();
                if (msg != null && msg.length() > 300) msg = msg.substring(0, 300);
                Log.e(TAG, (isContentLib(lib) ? "CSARM_LIB_FAIL_CONTENT " : "CSARM_LIB_FAIL ") + lib + " :: " + msg);
                report.append(lib).append(" FAIL\n");
            }
        }
        Log.i(TAG, "CSARM_LOAD_DONE ok=" + loadOk + " errors=" + loadErrors);

        FrameLayout root = new FrameLayout(this);

        glView = new GLSurfaceView(this);
        glView.setEGLContextClientVersion(2);
        glView.setRenderer(this);
        root.addView(glView,
            new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT,
                                         FrameLayout.LayoutParams.MATCH_PARENT));

        status = new TextView(this);
        status.setText("csARM load: ok=" + loadOk + " errors=" + loadErrors
                       + "\n" + report);
        status.setTextColor(0xFF00FF00);
        status.setTextSize(11f);
        status.setPadding(12, 24, 12, 12);
        status.setGravity(Gravity.TOP);
        root.addView(status,
            new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT,
                                         FrameLayout.LayoutParams.WRAP_CONTENT));

        setContentView(root);
    }

    @Override
    public void onSurfaceCreated(GL10 gl, EGLConfig config) {
        GLES20.glClearColor(0.06f, 0.07f, 0.10f, 1.0f);
    }

    @Override
    public void onSurfaceChanged(GL10 gl, int w, int h) {
        GLES20.glViewport(0, 0, w, h);
        Log.i(TAG, "CSARM_SURFACE " + w + "x" + h);
    }

    @Override
    public void onDrawFrame(GL10 gl) {
        frames++;
        if (frames % 30 == 1) {
            Log.i(TAG, "CSARM_FRAME " + frames);
        }
        float t = (System.nanoTime() - t0ns()) * 1e-9f;

        // animated gradient background
        GLES20.glClearColor(0.06f + 0.04f * (float) Math.sin(t * 0.7),
                            0.07f + 0.05f * (float) Math.sin(t * 1.1 + 2.0),
                            0.10f + 0.06f * (float) Math.sin(t * 1.3 + 4.0), 1.0f);
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT);

        // rotating triangle
        float ang = t * 1.2f;
        float r = 0.45f;
        float cx = 0.0f, cy = -0.05f;
        float[] tri = new float[9];
        for (int i = 0; i < 3; i++) {
            float a = ang + i * (float) (2.0 * Math.PI / 3.0);
            tri[i * 3]     = cx + r * (float) Math.cos(a);
            tri[i * 3 + 1] = cy + r * (float) Math.sin(a);
            tri[i * 3 + 2] = 0f;
        }
        drawTriangle(tri,
            0.9f + 0.1f * (float) Math.sin(t),
            0.55f + 0.3f * (float) Math.sin(t + 1.0),
            0.25f);
    }

    static long t0 = -1;
    static long t0ns() { if (t0 < 0) t0 = System.nanoTime(); return t0; }

    static final String VS =
        "attribute vec4 aPos;\n" +
        "attribute vec4 aCol;\n" +
        "varying vec4 vCol;\n" +
        "void main(){ gl_Position = aPos; vCol = aCol; }\n";
    static final String FS =
        "precision mediump float;\n" +
        "varying vec4 vCol;\n" +
        "void main(){ gl_FragColor = vCol; }\n";

    int prog = 0;
    void drawTriangle(float[] tri, float r, float g, float b) {
        if (prog == 0) {
            int v = GLES20.glCreateShader(GLES20.GL_VERTEX_SHADER);
            GLES20.glShaderSource(v, VS); GLES20.glCompileShader(v);
            int f = GLES20.glCreateShader(GLES20.GL_FRAGMENT_SHADER);
            GLES20.glShaderSource(f, FS); GLES20.glCompileShader(f);
            prog = GLES20.glCreateProgram();
            GLES20.glAttachShader(prog, v);
            GLES20.glAttachShader(prog, f);
            GLES20.glLinkProgram(prog);
        }
        GLES20.glUseProgram(prog);
        java.nio.FloatBuffer vb = java.nio.ByteBuffer
            .allocateDirect(tri.length * 4)
            .order(java.nio.ByteOrder.nativeOrder())
            .asFloatBuffer();
        vb.put(tri).position(0);
        float[] col = { r, g, b, 1f,  r, b, g, 1f,  g, r, b, 1f };
        java.nio.FloatBuffer cb = java.nio.ByteBuffer
            .allocateDirect(col.length * 4)
            .order(java.nio.ByteOrder.nativeOrder())
            .asFloatBuffer();
        cb.put(col).position(0);

        int aPos = GLES20.glGetAttribLocation(prog, "aPos");
        int aCol = GLES20.glGetAttribLocation(prog, "aCol");
        GLES20.glEnableVertexAttribArray(aPos);
        GLES20.glVertexAttribPointer(aPos, 3, GLES20.GL_FLOAT, false, 0, vb);
        GLES20.glEnableVertexAttribArray(aCol);
        GLES20.glVertexAttribPointer(aCol, 4, GLES20.GL_FLOAT, false, 0, cb);
        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, 3);
        GLES20.glDisableVertexAttribArray(aPos);
        GLES20.glDisableVertexAttribArray(aCol);
    }
}
