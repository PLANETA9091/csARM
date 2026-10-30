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
        "inputsystem", "engine", "client", "server", "launcher",
        "bzip2", "tier3", "dmxloader", "bitmap", "vtf", "shaderlib", "scenefilecache",
        "filesystem_stdio"
    };

    static int loadErrors = 0;
    static int loadOk = 0;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        loadPortLibraries();
        prepareArgsAndContent();
        super.onCreate(savedInstanceState);
    }

    private void loadPortLibraries() {
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
                Log.e(TAG, "CSARM_LIB_FAIL " + lib + " :: " + msg);
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
        } else {
            // fast boot defaults (no intro video, windowed, threaded engine)
            sb.append("-novid\n");
            sb.append("-windowed\n");
            sb.append("-w 1280\n-h 720\n");
            sb.append("-nobreakpad\n-nojoy\n");
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
