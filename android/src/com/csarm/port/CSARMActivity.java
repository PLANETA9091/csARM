package com.csarm.port;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

import org.libsdl.app.SDLActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * csARM full-engine activity.
 *
 * SDLActivity's static initializer loads libSDL2.so + libmain.so (our native
 * launcher). This subclass then preloads every ported library in dependency
 * order, materializes the game content skeleton (assets/cstrike -> filesDir)
 * and the launch-args file, and lets SDL boot the engine through
 * SDL_main -> LauncherMain (Valve's CSourceAppSystemGroup host).
 *
 * logcat contract for CI:
 *   CSARM_LIB_OK/FAIL <lib>   — per-library dlopen result
 *   CSARM_LOAD_DONE ok=N errors=M
 *   CSARM_ARGS_READY          — args + content skeleton in place
 */
public class CSARMActivity extends SDLActivity {
    static final String TAG = "CSARM";

    static final String[] LIBS = {
        "c++_shared",
        "protobuf", "tier0", "tier1", "tier2", "vstdlib", "mathlib",
        "appframework", "datacache", "studiorender", "soundemittersystem",
        "vguimatsurface", "vgui", "vgui_controls", "materialsystem",
        "inputsystem", "engine", "png", "kv3", "client", "server", "launcher",
        "bzip2", "tier3", "dmxloader", "bitmap", "vtf", "shaderlib", "scenefilecache",
        "filesystem_stdio",
        // round 55: real render stack (togl must precede shaderapidx9 —
        // DT_NEEDED would load it anyway, but the smoke order documents it).
        // round 56a: stdshader_dx9 is NOT dlopened while the engine runs
        // -noshaderapi — its static initializers register the real shader
        // classes into shaderlib's CShaderDLL and materialsystem initializes
        // them against the stub API (Spritecard SEGV, run #193 SwiftShader
        // tombstone).  The lib stays packed in the APK; run #193 already
        // proved it dlopens cleanly on both ABIs (ok=33).
        "togl", "shaderapidx9"
    };

    // round 56b: the real renderer is active when the effective args do NOT
    // carry -noshaderapi (intent extra > staged csarm.args > built-in
    // defaults, the same precedence prepareArgsAndContent implements).
    // stdshader_dx9 may only be dlopened in that mode — its static
    // initializers register the real shader classes (run #193).
    private boolean realRendererMode() {
        Intent in = getIntent();
        String extra = in != null ? in.getStringExtra("args") : null;
        if (extra != null && !extra.trim().isEmpty()) {
            return !extra.contains("-noshaderapi");
        }
        File f = new File(getFilesDir(), "csarm.args");
        if (f.exists()) {
            try {
                java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f));
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = r.readLine()) != null) sb.append(line).append('\n');
                r.close();
                return !sb.toString().contains("-noshaderapi");
            } catch (Throwable t) {
                Log.w(TAG, "CSARM_ARGS read failed: " + t);
            }
        }
        return false; // built-in defaults carry -noshaderapi
    }

    static int loadErrors = 0;
    static int loadOk = 0;

    // game DLLs are content-path (engine loads them at map load, not at boot):
    // failures are tagged CSARM_LIB_FAIL_CONTENT so CI can warn instead of
    // failing the boot-path assertion while the content stack is being ported
    static boolean isContentLib(String lib) {
        return lib.equals("client") || lib.equals("server");
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        boolean realRender = realRendererMode();
        Log.i(TAG, "CSARM_REAL_RENDER " + realRender);
        loadPortLibraries(realRender);
        prepareArgsAndContent();
        super.onCreate(savedInstanceState);
    }

    private void loadPortLibraries(boolean realRender) {
        StringBuilder report = new StringBuilder();
        java.util.ArrayList<String> libs = new java.util.ArrayList<>(java.util.Arrays.asList(LIBS));
        if (realRender) {
            // togl/shaderapidx9 are already in LIBS; stdshader_dx9 joins only
            // when the real renderer will consume it
            if (!libs.contains("stdshader_dx9")) libs.add("stdshader_dx9");
        }
        for (String lib : libs) {
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
    }

    private void prepareArgsAndContent() {
        File files = getFilesDir();
        // 1) content skeleton: assets/cstrike/** -> files/cstrike/**
        try {
            copyAssetDir("cstrike", new File(files, "cstrike"));
        } catch (IOException e) {
            Log.w(TAG, "CSARM_CONTENT asset copy failed: " + e.getMessage());
        }

        // 2) launch args: intent extra "args" overrides defaults
        StringBuilder sb = new StringBuilder();
        Intent in = getIntent();
        String extra = in != null ? in.getStringExtra("args") : null;
        if (extra != null && !extra.trim().isEmpty()) {
            sb.append(extra.trim()).append("\n");
        } else if (new File(files, "csarm.args").exists()) {
            // a staged csarm.args (map-load probe pushes one via adb root)
            // wins over the built-in defaults — otherwise this method would
            // clobber it on every start and the probe would boot the menu
            // instead of +map (run #152)
            sb.setLength(0);
            Log.i(TAG, "CSARM_ARGS_READY keep existing csarm.args");
            return;
        } else {
            // fast boot defaults (no intro video, windowed, threaded engine)
            sb.append("-novid\n");
            sb.append("-windowed\n");
            sb.append("-w 1280\n-h 720\n");
            sb.append("-nobreakpad\n-nojoy\n");
            // launcher loads shaderapiempty.so instead of the (unported)
            // shaderapidx9 — without this CMaterialSystem dlopens shaderapidx9,
            // fails, and the engine silently hangs before the first tick
            sb.append("-noshaderapi\n");
            // round 26: -no_scaleform_menu_on_boot — no Scaleform runtime is
            // shipped; without the flag the client SIGSEGVs in
            // CCreateMainMenuScreenScaleform::LoadDialog (NULL g_pScaleformUI)
            // at CEngineVGui::Init -> ActivateGameUI (run #161 tombstone)
            sb.append("-no_scaleform_menu_on_boot\n");
            sb.append("-basedir ").append(files.getAbsolutePath()).append("\n");
            sb.append("-game cstrike\n");
            sb.append("+host_thread_mode 2\n");
            sb.append("+mat_queue_mode 2\n");
            sb.append("+cl_threaded_bone_setup 1\n");
        }
        try {
            FileOutputStream f = new FileOutputStream(new File(files, "csarm.args"));
            f.write(sb.toString().getBytes("UTF-8"));
            f.close();
            Log.i(TAG, "CSARM_ARGS_READY " + sb.toString().replace('\n', ' '));
        } catch (IOException e) {
            Log.e(TAG, "CSARM_ARGS_READY FAIL " + e.getMessage());
        }
    }

    /** Recursively copy an assets directory to disk (filesDir/cstrike). */
    private void copyAssetDir(String assetPath, File target) throws IOException {
        String[] list = getAssets().list(assetPath);
        if (list == null || list.length == 0) {
            // plain file
            File out = target;
            out.getParentFile().mkdirs();
            InputStream is = getAssets().open(assetPath);
            OutputStream os = new FileOutputStream(out);
            byte[] buf = new byte[8192];
            int n;
            while ((n = is.read(buf)) > 0) os.write(buf, 0, n);
            is.close(); os.close();
            return;
        }
        target.mkdirs();
        for (String name : list) {
            copyAssetDir(assetPath + "/" + name, new File(target, name));
        }
    }
}
