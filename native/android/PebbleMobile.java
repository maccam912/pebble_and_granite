package dev.pebblegranite.platform;
import android.app.Activity;
import android.content.Context;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

public final class PebbleMobile extends GodotPlugin {
    public PebbleMobile(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "PebbleMobile"; }
    private static native boolean initializeIrohNative(Context context);
    @UsedByGodot public boolean initializeIroh() {
        Activity activity = getActivity();
        if (activity == null) return false;
        try {
            System.loadLibrary("pebble_iroh.android");
            return initializeIrohNative(activity.getApplicationContext());
        } catch (LinkageError | RuntimeException error) { return false; }
    }
}
