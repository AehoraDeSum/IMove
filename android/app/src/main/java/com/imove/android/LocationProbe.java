package com.imove.android;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationManager;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import java.util.function.Consumer;

final class LocationProbe {
    private LocationProbe() {}

    static void once(Context context, Consumer<Location> success, Consumer<String> failure) {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            failure.accept("Precise location permission is required.");
            return;
        }
        LocationManager manager = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        if (manager == null || !manager.isLocationEnabled()) {
            failure.accept("Turn on the phone's location services.");
            return;
        }
        boolean gps = manager.isProviderEnabled(LocationManager.GPS_PROVIDER);
        boolean network = manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
        if (!gps && !network) {
            failure.accept("GPS or network location is not enabled.");
            return;
        }
        Handler main = new Handler(Looper.getMainLooper());
        new Attempt(manager, main, gps, network, success, failure).next();
    }

    private static final class Attempt {
        private final LocationManager manager;
        private final Handler main;
        private final boolean gps;
        private final boolean network;
        private final Consumer<Location> success;
        private final Consumer<String> failure;
        private int index = 0;

        Attempt(LocationManager manager, Handler main, boolean gps, boolean network,
                Consumer<Location> success, Consumer<String> failure) {
            this.manager = manager;
            this.main = main;
            this.gps = gps;
            this.network = network;
            this.success = success;
            this.failure = failure;
        }

        void next() {
            String provider;
            if (index == 0 && gps) {
                index = 1;
                provider = LocationManager.GPS_PROVIDER;
            } else if (index <= 1 && network) {
                index = 2;
                provider = LocationManager.NETWORK_PROVIDER;
            }
            else { failure.accept("Could not get a current location; check GPS and network location."); return; }
            request(provider);
        }

        private void request(String provider) {
        CancellationSignal cancellation = new CancellationSignal();
        final boolean[] completed = {false};
        Runnable timeout = () -> {
            if (!completed[0]) {
                completed[0] = true;
                cancellation.cancel();
                next();
            }
        };
        main.postDelayed(timeout, 20_000);
        try {
            manager.getCurrentLocation(provider, cancellation, main::post, location -> {
                if (completed[0]) return;
                completed[0] = true;
                main.removeCallbacks(timeout);
                long age = location == null ? Long.MAX_VALUE :
                        SystemClock.elapsedRealtimeNanos() - location.getElapsedRealtimeNanos();
                if (location == null || age > 120_000_000_000L ||
                        !location.hasAccuracy() || location.getAccuracy() > 200f) next();
                else success.accept(location);
            });
        } catch (SecurityException error) {
            if (!completed[0]) {
                completed[0] = true;
                main.removeCallbacks(timeout);
                failure.accept("Location permission was revoked. Grant it again.");
            }
        } catch (RuntimeException error) {
            if (!completed[0]) {
                completed[0] = true;
                main.removeCallbacks(timeout);
                next();
            }
        }
        }
    }
}
