package com.imove.android;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.location.Location;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import java.text.DateFormat;
import java.util.Date;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class TrackingService extends Service {
    static final String ACTION_START = "com.imove.android.START_TRACKING";
    static final String ACTION_STOP = "com.imove.android.STOP_TRACKING";
    private static final String CHANNEL = "imove_location";
    private static final int NOTIFICATION_ID = 14;
    private static final long INTERVAL_MS = 5 * 60 * 1000L;
    static volatile boolean running = false;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService network = Executors.newSingleThreadExecutor();
    private boolean inFlight = false;
    private boolean stopping = false;
    private boolean trackingActivated = false;
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            if (!running || stopping) return;
            if (!inFlight) collectAndSend();
            main.postDelayed(this, INTERVAL_MS);
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        NotificationChannel channel = new NotificationChannel(CHANNEL, "IMove location tracking", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Shown while your location is being sent to the Mac.");
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if (running) return START_NOT_STICKY;
        try {
            Settings.load(this);
            startForeground(NOTIFICATION_ID, notification("Getting the first location…"), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
            running = true;
            stopping = false;
            main.post(tick);
        } catch (RuntimeException error) {
            Settings.setLastResult(this, "Could not start tracking: " + error.getMessage());
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    private void collectAndSend() {
        inFlight = true;
        LocationProbe.once(this, this::send, message -> finish("Could not get location: " + message));
    }

    private void send(Location location) {
        if (!running || stopping) { inFlight = false; return; }
        network.execute(() -> {
            String result;
            try {
                EndpointConfig config = Settings.load(this);
                LocationPoint point = LocationPoint.parse(
                        Double.toString(location.getLatitude()), Double.toString(location.getLongitude()));
                if (!trackingActivated) {
                    ImoveApi.activateTracking(config);
                    trackingActivated = true;
                }
                ImoveApi.sendTracking(config, point);
                result = "Sent · " + DateFormat.getTimeInstance(DateFormat.SHORT).format(new Date()) +
                        " · about ±" + Math.round(location.getAccuracy()) + " m";
            } catch (Exception error) {
                result = "Could not send: " + error.getMessage();
            }
            String finalResult = result;
            main.post(() -> finish(finalResult));
        });
    }

    private void finish(String result) {
        inFlight = false;
        if (!running || stopping) return;
        Settings.setLastResult(this, result);
        getSystemService(NotificationManager.class).notify(NOTIFICATION_ID, notification(result));
    }

    private Notification notification(String text) {
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent content = PendingIntent.getActivity(this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Intent stop = new Intent(this, TrackingService.class).setAction(ACTION_STOP);
        PendingIntent stopAction = PendingIntent.getService(this, 1, stop,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_imove_notification)
                .setContentTitle("IMove · 5-minute location relay")
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setOngoing(true)
                .setContentIntent(content)
                .addAction(android.R.drawable.ic_media_pause, "Stop", stopAction)
                .build();
    }

    @Override public void onDestroy() {
        stopping = true;
        running = false;
        main.removeCallbacks(tick);
        network.shutdownNow();
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
