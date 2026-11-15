package com.imove.android;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.ColorDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.WindowInsets;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;
import android.net.Uri;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ImageView;
import android.widget.ScrollView;
import android.widget.HorizontalScrollView;
import android.widget.TextView;

import org.json.JSONObject;
import org.json.JSONArray;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final int BG = Color.rgb(8, 22, 16);
    private static final int SIDEBAR = Color.rgb(9, 33, 22);
    private static final int PANEL = Color.rgb(18, 42, 30);
    private static final int PANEL_RAISED = Color.rgb(24, 55, 39);
    private static final int LINE = Color.rgb(42, 77, 54);
    private static final int ACCENT = Color.rgb(74, 224, 131);
    private static final int TEXT = Color.rgb(239, 255, 243);
    private static final int MUTED = Color.rgb(166, 190, 173);
    private static final String[] PAGES = {"Location", "Map", "Saved places", "Routes", "Tracking", "Connection"};
    private static final int REQUEST_LOCATION = 10;
    private static final int REQUEST_NOTIFICATION = 11;
    private final ExecutorService network = Executors.newSingleThreadExecutor();
    private EditText address, code, latitude, longitude, placeName, routeName, routeMinutes, routeSeconds, updateInterval;
    private TextView message, trackingStatus, activeRouteStatus, refreshStatus;
    private CheckBox autoRenew;
    private LinearLayout placesContainer;
    private LinearLayout quickPlacesContainer;
    private LinearLayout mapContainer;
    private LinearLayout routeDraftContainer, routesContainer, routeTotalFields, routeLegFields;
    private WebView mapView;
    private Dialog mapDialog;
    private TextView fullMapHint;
    private Button routeModeButton;
    private Button routeTimingButton;
    private LocationPoint lastSentPoint;
    private final ArrayList<LocationPoint> routeDraftPoints = new ArrayList<>();
    private final ArrayList<Integer> routeLegDurations = new ArrayList<>();
    private final ArrayList<JSONArray> routeLegPaths = new ArrayList<>();
    private final ArrayList<String> routeLegDescriptions = new ArrayList<>();
    private final ArrayList<ArrayList<LocationPoint>> routeViaPoints = new ArrayList<>();
    private int editingLegIndex = -1;
    private JSONArray railCatalogue;
    private final ArrayList<EditText> routeLegMinuteFields = new ArrayList<>();
    private final ArrayList<EditText> routeLegSecondFields = new ArrayList<>();
    private boolean routeCustomTiming = false;
    private final Handler routeHandler = new Handler(Looper.getMainLooper());
    private boolean routeMode = false;
    private final Runnable routePoll = new Runnable() {
        @Override public void run() {
            if (!Settings.url(MainActivity.this).isEmpty()) refreshRouteStatus();
            routeHandler.postDelayed(this, 5000);
        }
    };
    private boolean waitingToTrack = false;
    private boolean waitingForCurrent = false;
    private boolean waitingForMap = false;
    private final LinkedHashMap<LinearLayout, String> pageCards = new LinkedHashMap<>();
    private ScrollView mainScroll;
    private TextView pageTitle, pageSubtitle;
    private String currentPage = "Connection";

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        buildScreen();
        address.setText(Settings.url(this));
        code.setText(Settings.token(this));
        showStatus("Waiting for the Mac connection.");
    }

    @Override protected void onResume() {
        super.onResume();
        if (trackingStatus != null) {
            trackingStatus.setText(TrackingService.running
                    ? "5-minute relay is on. " + Settings.lastResult(this)
                    : "5-minute relay is off. " + Settings.lastResult(this));
        }
        routeHandler.removeCallbacks(routePoll);
        routeHandler.postDelayed(routePoll, 5000);
    }

    @Override protected void onPause() {
        routeHandler.removeCallbacks(routePoll);
        super.onPause();
    }

    private void buildScreen() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        LinearLayout toolbar = new LinearLayout(this);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(dp(18), dp(11), dp(18), dp(11));
        toolbar.setBackgroundColor(SIDEBAR);
        TextView menu = text("☰", 25, ACCENT);
        menu.setGravity(Gravity.CENTER);
        menu.setBackground(round(PANEL_RAISED, 12, LINE));
        toolbar.addView(menu, new LinearLayout.LayoutParams(dp(44), dp(44)));
        menu.setOnClickListener(view -> openMenu());
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.ic_imove);
        LinearLayout.LayoutParams logoParams = new LinearLayout.LayoutParams(dp(42), dp(42));
        logoParams.leftMargin = dp(13);
        toolbar.addView(logo, logoParams);
        TextView appName = text("IMove", 22, TEXT);
        appName.setTypeface(null, Typeface.BOLD);
        LinearLayout.LayoutParams nameParams = new LinearLayout.LayoutParams(-2, -2);
        nameParams.leftMargin = dp(7);
        toolbar.addView(appName, nameParams);
        root.addView(toolbar, new LinearLayout.LayoutParams(-1, -2));

        mainScroll = new ScrollView(this);
        mainScroll.setFillViewport(true);
        mainScroll.setBackgroundColor(BG);
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setPadding(dp(18), dp(25), dp(18), dp(28));
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
            toolbar.setPadding(dp(18), bars.top + dp(11), dp(18), dp(11));
            column.setPadding(dp(18), dp(25), dp(18), bars.bottom + dp(28));
            return insets;
        });
        mainScroll.addView(column);
        root.addView(mainScroll, new LinearLayout.LayoutParams(-1, 0, 1));

        TextView eyebrow = text("IMOVE  /  MOBILE", 11, ACCENT);
        eyebrow.setLetterSpacing(0.12f);
        column.addView(eyebrow);
        pageTitle = text("Connection", 31, TEXT);
        pageTitle.setTypeface(null, Typeface.BOLD);
        pageTitle.setPadding(0, dp(5), 0, dp(5));
        column.addView(pageTitle);
        pageSubtitle = text("Connect to your Mac over a private network.", 14, MUTED);
        LinearLayout.LayoutParams subtitleParams = new LinearLayout.LayoutParams(-1, -2);
        subtitleParams.bottomMargin = dp(20);
        column.addView(pageSubtitle, subtitleParams);

        message = text("", 14, TEXT);
        message.setPadding(dp(14), dp(13), dp(14), dp(13));
        message.setBackground(round(PANEL_RAISED, 12, LINE));
        LinearLayout.LayoutParams messageParams = new LinearLayout.LayoutParams(-1, -2);
        messageParams.bottomMargin = dp(12);
        column.addView(message, messageParams);

        LinearLayout connectionCard = card(column);
        pageCards.put(connectionCard, "Connection");
        heading(connectionCard, "Secure connection");
        connectionCard.addView(text("The Mac and this phone must be on the same private Tailscale network.", 14, MUTED));
        address = field(connectionCard, "Private HTTPS address", "https://mac.…ts.net", false);
        code = field(connectionCard, "IMove pairing code", "32-character code", true);
        CheckBox showCode = new CheckBox(this);
        showCode.setText("Show code");
        showCode.setTextColor(MUTED);
        showCode.setButtonTintList(android.content.res.ColorStateList.valueOf(ACCENT));
        showCode.setOnCheckedChangeListener((view, visible) -> {
            int cursor = code.getSelectionStart();
            code.setInputType(visible ? InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
                    : InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
            code.setSelection(Math.max(0, Math.min(cursor, code.length())));
        });
        connectionCard.addView(showCode);
        button(connectionCard, "Sign in", this::checkConnection);
        button(connectionCard, "Sign out", () -> {
            haltTrackingForManual();
            Settings.signOut(this);
            code.setText("");
            showStatus("The pairing code was removed from this phone. Enter it again to reconnect.");
        });

        LinearLayout sendCard = card(column);
        pageCards.put(sendCard, "Location");
        heading(sendCard, "Send a location");
        latitude = field(sendCard, "Enlem", "41.0082", false);
        longitude = field(sendCard, "Boylam", "28.9784", false);
        TextView quickTitle = text("SAVED PLACES", 11, MUTED);
        quickTitle.setLetterSpacing(0.1f);
        quickTitle.setPadding(0, dp(12), 0, dp(7));
        sendCard.addView(quickTitle);
        HorizontalScrollView quickScroll = new HorizontalScrollView(this);
        quickScroll.setHorizontalScrollBarEnabled(false);
        quickPlacesContainer = new LinearLayout(this);
        quickPlacesContainer.setOrientation(LinearLayout.HORIZONTAL);
        quickScroll.addView(quickPlacesContainer);
        sendCard.addView(quickScroll);
        quickPlacesContainer.addView(text("Saved places will appear here once you connect.", 13, MUTED));
        button(sendCard, "Add place", () -> showPage("Saved places"));
        autoRenew = new CheckBox(this);
        autoRenew.setText("Auto-refresh this location on the Mac");
        autoRenew.setTextColor(TEXT);
        autoRenew.setButtonTintList(android.content.res.ColorStateList.valueOf(ACCENT));
        sendCard.addView(autoRenew);
        button(sendCard, "Send to iPhone", this::sendEntered);
        button(sendCard, "Send my current location", this::sendCurrent);

        LinearLayout refreshCard = card(column);
        pageCards.put(refreshCard, "Location");
        heading(refreshCard, "USB refresh interval");
        refreshCard.addView(text("Fixed locations and route waypoints share this interval. A new USB command does not start until the previous one finishes.", 14, MUTED));
        updateInterval = field(refreshCard, "Resend at most every (1–60 seconds)", "1–60", false);
        updateInterval.setInputType(InputType.TYPE_CLASS_NUMBER);
        updateInterval.setText("20");
        button(refreshCard, "Save interval", this::saveUpdateInterval);
        refreshStatus = text("Reading refresh status…", 13, MUTED);
        refreshCard.addView(refreshStatus);
        button(refreshCard, "Stop fixed location refresh", this::stopRefresh);

        LinearLayout mapCard = card(column);
        pageCards.put(mapCard, "Map");
        heading(mapCard, "Pick on the map");
        mapCard.addView(text("Tapping the map fills in the coordinates to send. You can also show your phone's location on the map.", 14, MUTED));
        button(mapCard, "Open map", this::openMap);
        button(mapCard, "Full-screen map", this::openFullscreenMap);
        button(mapCard, "Show my phone's location on the map", this::showCurrentOnMap);
        mapContainer = new LinearLayout(this);
        mapContainer.setOrientation(LinearLayout.VERTICAL);
        mapCard.addView(mapContainer);

        LinearLayout routeCard = card(column);
        pageCards.put(routeCard, "Routes");
        heading(routeCard, "Routes");
        routeCard.addView(text("Choose stations on the B1 Marmaray, M2 and M6 lines; add walking paths and transfers. Reshape segments with waypoints.", 14, MUTED));
        routeCard.addView(text("Line geometry is approximate map data, not live service information. Review durations before saving.", 12, MUTED));
        routeCard.addView(text("Walking paths are calculated online on the Mac; if Apple Maps does not respond, FOSSGIS Valhalla is used.", 12, MUTED));
        button(routeCard, "Add rail section", () -> chooseRailAction(false));
        button(routeCard, "Walk to boarding station", () -> chooseRailAction(true));
        button(routeCard, "Edit segment on the map", this::chooseLegToEdit);
        button(routeCard, "Calculate walking path for selected segment", this::calculateSelectedWalk);
        routeModeButton = button(routeCard, "Start drawing route", this::toggleRouteMode);
        button(routeCard, "Undo last point", () -> {
            captureRouteLegFields();
            undoRoutePoint();
            renderRouteDraft();
        });
        button(routeCard, "Clear draft", () -> { clearRouteDraft(); renderRouteDraft(); });
        routeDraftContainer = new LinearLayout(this);
        routeDraftContainer.setOrientation(LinearLayout.VERTICAL);
        routeCard.addView(routeDraftContainer);
        routeName = field(routeCard, "Route name", "e.g. seaside route", false);
        routeTimingButton = button(routeCard, "Timing: split total time evenly", () -> {
            captureRouteLegFields();
            routeCustomTiming = !routeCustomTiming;
            renderRouteTiming();
        });
        routeTotalFields = new LinearLayout(this);
        routeTotalFields.setOrientation(LinearLayout.VERTICAL);
        routeCard.addView(routeTotalFields);
        routeMinutes = field(routeTotalFields, "Total duration (minutes)", "Minutes", false);
        routeMinutes.setInputType(InputType.TYPE_CLASS_NUMBER);
        routeMinutes.setText("5");
        routeSeconds = field(routeTotalFields, "Extra seconds (0–59)", "Seconds", false);
        routeSeconds.setInputType(InputType.TYPE_CLASS_NUMBER);
        routeSeconds.setText("0");
        routeLegFields = new LinearLayout(this);
        routeLegFields.setOrientation(LinearLayout.VERTICAL);
        routeCard.addView(routeLegFields);
        renderRouteTiming();
        button(routeCard, "Save route", this::saveRoute);
        button(routeCard, "Refresh routes", this::loadRoutes);
        activeRouteStatus = text("No active route.", 14, ACCENT);
        activeRouteStatus.setPadding(0, dp(10), 0, dp(10));
        routeCard.addView(activeRouteStatus);
        button(routeCard, "Stop route", this::stopRoute);
        routesContainer = new LinearLayout(this);
        routesContainer.setOrientation(LinearLayout.VERTICAL);
        routeCard.addView(routesContainer);

        LinearLayout placesCard = card(column);
        pageCards.put(placesCard, "Saved places");
        heading(placesCard, "Saved places");
        placesCard.addView(text("Save the coordinate chosen on the Location screen under a name. The list appears on all paired devices.", 14, MUTED));
        button(placesCard, "Choose location", () -> showPage("Location"));
        placeName = field(placesCard, "Place name", "e.g. home", false);
        button(placesCard, "Save these coordinates", this::savePlace);
        button(placesCard, "Refresh list", this::loadPlaces);
        placesContainer = new LinearLayout(this);
        placesContainer.setOrientation(LinearLayout.VERTICAL);
        placesCard.addView(placesContainer);

        LinearLayout trackingCard = card(column);
        pageCards.put(trackingCard, "Tracking");
        heading(trackingCard, "5-minute relay");
        trackingCard.addView(text("Runs with a visible notification. It keeps trying with the screen off, though power management may delay it. Turn it on again after restarting the phone.", 14, MUTED));
        trackingStatus = text("5-minute relay is off.", 14, ACCENT);
        trackingStatus.setPadding(0, dp(12), 0, dp(8));
        trackingCard.addView(trackingStatus);
        button(trackingCard, "Start 5-minute relay", this::startTracking);
        button(trackingCard, "Stop relay", this::stopTracking);

        LinearLayout clearCard = card(column);
        pageCards.put(clearCard, "Location");
        heading(clearCard, "Remove location");
        clearCard.addView(text("The iPhone may return to its real location. An active relay is stopped first.", 14, MUTED));
        button(clearCard, "Remove simulated location", this::confirmClear);

        setContentView(root);
        showPage("Connection");
        renderRouteDraft();
    }

    private void showPage(String page) {
        currentPage = page;
        for (Map.Entry<LinearLayout, String> entry : pageCards.entrySet()) {
            entry.getKey().setVisibility(page.equals(entry.getValue()) ? View.VISIBLE : View.GONE);
        }
        if (pageTitle != null) pageTitle.setText(page);
        if (pageSubtitle != null) {
            String subtitle;
            switch (page) {
                case "Location": subtitle = "Choose, send and refresh a location."; break;
                case "Map": subtitle = "Pick a place or route point on the map."; break;
                case "Saved places": subtitle = "Manage your favorite places with one tap."; break;
                case "Routes": subtitle = "Set points and the duration of each leg."; break;
                case "Tracking": subtitle = "Relay your phone's location regularly."; break;
                default: subtitle = "Connect to your Mac over a private network.";
            }
            pageSubtitle.setText(subtitle);
        }
        if (mainScroll != null) mainScroll.post(() -> mainScroll.smoothScrollTo(0, 0));
    }

    private void openMenu() {
        Dialog dialog = new Dialog(this);
        LinearLayout drawer = new LinearLayout(this);
        drawer.setOrientation(LinearLayout.VERTICAL);
        drawer.setPadding(dp(20), dp(50), dp(20), dp(22));
        drawer.setBackgroundColor(SIDEBAR);
        TextView brand = text("◎  IMove", 27, TEXT);
        brand.setTypeface(null, Typeface.BOLD);
        drawer.addView(brand);
        TextView caption = text("LOCATION CONTROL", 11, MUTED);
        caption.setLetterSpacing(0.13f);
        LinearLayout.LayoutParams captionParams = new LinearLayout.LayoutParams(-1, -2);
        captionParams.bottomMargin = dp(30);
        drawer.addView(caption, captionParams);
        String[] marks = {"⌖", "◉", "▤", "↗", "◷", "⚙"};
        for (int index = 0; index < PAGES.length; index++) {
            String page = PAGES[index];
            TextView item = text(marks[index] + "   " + page, 16, page.equals(currentPage) ? TEXT : MUTED);
            item.setGravity(Gravity.CENTER_VERTICAL);
            item.setPadding(dp(16), 0, dp(16), 0);
            item.setBackground(round(page.equals(currentPage) ? PANEL_RAISED : SIDEBAR, 12, 0));
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, dp(52));
            params.bottomMargin = dp(5);
            drawer.addView(item, params);
            item.setOnClickListener(view -> { dialog.dismiss(); showPage(page); });
        }
        View spacer = new View(this);
        drawer.addView(spacer, new LinearLayout.LayoutParams(1, 0, 1));
        drawer.addView(text("MAC  /  MOBILE  ·  1.1.0", 11, MUTED));
        dialog.setContentView(drawer);
        dialog.show();
        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.setGravity(Gravity.START | Gravity.TOP);
            window.setLayout(dp(310), WindowManager.LayoutParams.MATCH_PARENT);
            WindowManager.LayoutParams attributes = window.getAttributes();
            attributes.dimAmount = 0.58f;
            window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            window.setAttributes(attributes);
        }
    }

    private void checkConnection() {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        showStatus("Contacting the Mac…");
        network.execute(() -> {
            try {
                JSONObject status = ImoveApi.status(config);
                JSONArray places = ImoveApi.places(config).getJSONArray("places");
                JSONArray routes = ImoveApi.routes(config).getJSONArray("routes");
                runOnUiThread(() -> {
                    String last = status.optString("lastSent", "");
                    String[] parts = last.split(",");
                    lastSentPoint = null;
                    if (parts.length == 2) {
                        try { lastSentPoint = LocationPoint.parse(parts[0], parts[1]); }
                        catch (IllegalArgumentException ignored) { lastSentPoint = null; }
                    }
                    showStatus(status.optBoolean("ready", false)
                            ? "Mac and iPhone connection ready."
                            : "Connected to the Mac; choose the USB target in IMove.");
                    renderPlaces(places);
                    renderRoutes(routes);
                    renderActiveRoute(status);
                    renderRefreshStatus(status);
                    showPage("Location");
                });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Operation failed: " + error.getMessage()));
            }
        });
    }

    private void openMap() {
        LocationPoint point;
        try { point = LocationPoint.parse(latitude.getText().toString(), longitude.getText().toString()); }
        catch (IllegalArgumentException error) { point = lastSentPoint; }
        if (point == null) point = LocationPoint.parse("41.0082", "28.9784");
        loadMapAt(point, false);
    }

    private void showCurrentOnMap() {
        if (saveConfig() == null) return;
        waitingForMap = true;
        if (!hasFineLocation()) { askLocation(); return; }
        collectMapCurrent();
    }

    private void collectMapCurrent() {
        waitingForMap = false;
        showStatus("Getting the phone's location for the map…");
        LocationProbe.once(this, location -> {
            LocationPoint point = LocationPoint.parse(
                    Double.toString(location.getLatitude()), Double.toString(location.getLongitude()));
            loadMapAt(point, true);
            showStatus("Showing the phone's current location on the map; it was not sent to the iPhone.");
        }, this::showStatus);
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void loadMapAt(LocationPoint point, boolean currentPhoneLocation) {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        if (mapView == null) {
            mapView = new WebView(this);
            mapView.getSettings().setAllowFileAccess(false);
            mapView.getSettings().setAllowContentAccess(false);
            mapView.getSettings().setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
            mapView.getSettings().setJavaScriptCanOpenWindowsAutomatically(false);
            mapView.getSettings().setJavaScriptEnabled(true);
            mapView.getSettings().setDomStorageEnabled(false);
            mapView.getSettings().setUserAgentString(mapView.getSettings().getUserAgentString() + " IMove/1.1.0");
            mapView.setBackgroundColor(BG);
            mapView.setWebViewClient(new WebViewClient() {
                @Override public void onPageFinished(WebView view, String url) {
                    updateRouteMapOverlay();
                    if (routeMode && routeDraftPoints.size() >= 2) fitRouteMap();
                }
                @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    Uri uri = request.getUrl();
                    if ("imove-pick".equals(uri.getScheme()) && "point".equals(uri.getHost())) {
                        try {
                            LocationPoint selected = LocationPoint.parse(uri.getQueryParameter("latitude"),
                                    uri.getQueryParameter("longitude"));
                            if (routeMode) {
                                captureRouteLegFields();
                                if (editingLegIndex >= 0 && editingLegIndex < routeLegPaths.size()) {
                                    routeViaPoints.get(editingLegIndex).add(selected);
                                    ArrayList<LocationPoint> shape = new ArrayList<>();
                                    shape.add(routeDraftPoints.get(editingLegIndex));
                                    shape.addAll(routeViaPoints.get(editingLegIndex));
                                    shape.add(routeDraftPoints.get(editingLegIndex + 1));
                                    routeLegPaths.set(editingLegIndex, pathJson(shape));
                                    routeLegDescriptions.set(editingLegIndex, "Hand-edited segment");
                                    showStatus("Waypoint added to segment " + (editingLegIndex + 1) + ".");
                                } else {
                                    appendRoutePoint(selected, null, "Hand-drawn segment", 300);
                                    showStatus("Route point " + routeDraftPoints.size() + " added.");
                                }
                                renderRouteDraft();
                                if (fullMapHint != null) fullMapHint.setText(routeDraftPoints.size() + " route points selected · tap the map to continue");
                            } else {
                                fill(Double.toString(selected.latitude), Double.toString(selected.longitude));
                                showStatus("Map point selected. You can send or save it.");
                                showPage("Location");
                                if (mapDialog != null) mapDialog.dismiss();
                            }
                        } catch (Exception error) { showStatus("The map returned an invalid coordinate."); }
                        return true;
                    }
                    if ("https".equals(uri.getScheme()) && "www.openstreetmap.org".equals(uri.getHost())) {
                        startActivity(new Intent(Intent.ACTION_VIEW, uri));
                    }
                    return true;
                }
            });
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, dp(480));
            params.topMargin = dp(12);
            mapContainer.addView(mapView, params);
        }
        String fragment = "#native=1&latitude=" + point.latitude + "&longitude=" + point.longitude;
        if (lastSentPoint != null) fragment += "&lastLatitude=" + lastSentPoint.latitude + "&lastLongitude=" + lastSentPoint.longitude;
        if (currentPhoneLocation) fragment += "&currentLatitude=" + point.latitude + "&currentLongitude=" + point.longitude;
        mapView.loadUrl(config.baseUrl + "/map" + fragment);
    }

    private void openFullscreenMap() {
        if (mapView == null) openMap();
        if (mapView == null || mapDialog != null) return;
        Dialog dialog = new Dialog(this, android.R.style.Theme_Material_NoActionBar);
        LinearLayout screen = new LinearLayout(this);
        screen.setOrientation(LinearLayout.VERTICAL);
        screen.setBackgroundColor(BG);
        screen.setPadding(dp(14), dp(10), dp(14), dp(10));
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = text(routeMode ? "Pick route points" : "Pick a location on the map", 19, TEXT);
        title.setTypeface(null, Typeface.BOLD);
        header.addView(title, new LinearLayout.LayoutParams(0, dp(48), 1));
        TextView close = text("Close ×", 14, ACCENT);
        close.setGravity(Gravity.CENTER);
        close.setBackground(round(PANEL_RAISED, 10, LINE));
        header.addView(close, new LinearLayout.LayoutParams(dp(88), dp(42)));
        close.setOnClickListener(view -> dialog.dismiss());
        screen.addView(header);
        fullMapHint = text(routeMode ? routeDraftPoints.size() + " route points selected · tap the map"
                : "Tap the map; the chosen location is filled in for sending.", 13, MUTED);
        fullMapHint.setPadding(0, 0, 0, dp(12));
        screen.addView(fullMapHint);
        ViewGroup previousParent = (ViewGroup) mapView.getParent();
        if (previousParent != null) previousParent.removeView(mapView);
        screen.addView(mapView, new LinearLayout.LayoutParams(-1, 0, 1));
        dialog.setContentView(screen);
        dialog.setOnDismissListener(ignored -> {
            if (mapView != null) {
                ViewGroup parent = (ViewGroup) mapView.getParent();
                if (parent != null) parent.removeView(mapView);
                LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, dp(480));
                params.topMargin = dp(12);
                mapContainer.addView(mapView, params);
                mapView.evaluateJavascript("window.postMessage({type:'imove-resize'},location.origin);", null);
            }
            fullMapHint = null;
            mapDialog = null;
        });
        mapDialog = dialog;
        dialog.show();
        Window window = dialog.getWindow();
        if (window != null) {
            window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT);
            window.setStatusBarColor(SIDEBAR);
            window.setNavigationBarColor(BG);
        }
        mapView.evaluateJavascript("window.postMessage({type:'imove-resize'},location.origin);", null);
    }

    private void toggleRouteMode() {
        if (!routeMode && saveConfig() == null) return;
        routeMode = !routeMode;
        if (!routeMode) editingLegIndex = -1;
        routeModeButton.setText(routeMode ? "Finish drawing route" : "Start drawing route");
        if (routeMode && mapView == null) openMap();
        if (routeMode) showPage("Map");
        showStatus(routeMode ? "Tap the map to add route points in order." : "The map is back to single-location picking.");
    }

    private static JSONObject pointJson(LocationPoint point) {
        JSONObject object = new JSONObject();
        try { object.put("latitude", point.latitude); object.put("longitude", point.longitude); }
        catch (Exception ignored) { }
        return object;
    }

    private static JSONArray pathJson(ArrayList<LocationPoint> points) {
        JSONArray path = new JSONArray();
        for (LocationPoint point : points) path.put(pointJson(point));
        return path;
    }

    private static JSONArray directPath(LocationPoint start, LocationPoint end) {
        JSONArray path = new JSONArray(); path.put(pointJson(start)); path.put(pointJson(end)); return path;
    }

    private void appendRoutePoint(LocationPoint point, JSONArray path, String description, int seconds) {
        if (!routeDraftPoints.isEmpty()) {
            LocationPoint previous = routeDraftPoints.get(routeDraftPoints.size() - 1);
            routeLegPaths.add(path != null ? path : directPath(previous, point));
            routeLegDescriptions.add(description);
            routeViaPoints.add(new ArrayList<>());
            routeLegDurations.add(seconds);
        }
        routeDraftPoints.add(point);
    }

    private void undoRoutePoint() {
        if (routeDraftPoints.isEmpty()) return;
        routeDraftPoints.remove(routeDraftPoints.size() - 1);
        if (!routeLegPaths.isEmpty()) routeLegPaths.remove(routeLegPaths.size() - 1);
        if (!routeLegDescriptions.isEmpty()) routeLegDescriptions.remove(routeLegDescriptions.size() - 1);
        if (!routeViaPoints.isEmpty()) routeViaPoints.remove(routeViaPoints.size() - 1);
        if (!routeLegDurations.isEmpty()) routeLegDurations.remove(routeLegDurations.size() - 1);
        editingLegIndex = -1;
    }

    private void clearRouteDraft() {
        routeDraftPoints.clear(); routeLegPaths.clear(); routeLegDescriptions.clear();
        routeViaPoints.clear(); routeLegDurations.clear(); editingLegIndex = -1;
    }

    private static LocationPoint stationPoint(JSONObject station) {
        return LocationPoint.parse(Double.toString(station.optDouble("latitude")),
                Double.toString(station.optDouble("longitude")));
    }

    private static double meters(LocationPoint a, LocationPoint b) {
        return Math.hypot((a.latitude - b.latitude) * 111000,
                (a.longitude - b.longitude) * 111000 * Math.cos(Math.toRadians(a.latitude)));
    }

    private void chooseRailAction(boolean walk) {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        if (railCatalogue != null) { showRailLines(walk); return; }
        showStatus("Loading line data…");
        network.execute(() -> {
            try {
                JSONArray lines = ImoveApi.transit(config).getJSONArray("lines");
                runOnUiThread(() -> { railCatalogue = lines; showRailLines(walk); });
            } catch (Exception error) { runOnUiThread(() -> showStatus("Could not get line data: " + error.getMessage())); }
        });
    }

    private void showRailLines(boolean walk) {
        if (railCatalogue == null) return;
        String[] labels = new String[railCatalogue.length()];
        for (int i = 0; i < labels.length; i++) {
            JSONObject line = railCatalogue.optJSONObject(i);
            labels[i] = line == null ? "?" : line.optString("id") + " · " + line.optString("name");
        }
        new AlertDialog.Builder(this).setTitle("Choose line")
                .setItems(labels, (dialog, index) -> showRailBoard(railCatalogue.optJSONObject(index), walk))
                .setNegativeButton("Cancel", null).show();
    }

    private void showRailBoard(JSONObject line, boolean walk) {
        if (line == null) return;
        JSONArray stations = line.optJSONArray("stations");
        if (stations == null) return;
        String[] labels = new String[stations.length()];
        for (int i = 0; i < labels.length; i++) labels[i] = stations.optJSONObject(i).optString("name");
        new AlertDialog.Builder(this).setTitle(line.optString("id") + " · boarding station")
                .setItems(labels, (dialog, board) -> {
                    if (walk) walkToStation(line, board);
                    else new AlertDialog.Builder(this).setTitle(line.optString("id") + " · alighting station")
                            .setItems(labels, (nextDialog, alight) -> appendRailSection(line, board, alight))
                            .setNegativeButton("Cancel", null).show();
                }).setNegativeButton("Cancel", null).show();
    }

    private void walkToStation(JSONObject line, int board) {
        captureRouteLegFields();
        JSONObject station = line.optJSONArray("stations").optJSONObject(board);
        LocationPoint end = stationPoint(station);
        if (routeDraftPoints.isEmpty()) {
            appendRoutePoint(end, null, "", 0); renderRouteDraft();
            showStatus("Boarding station added as the starting point."); return;
        }
        LocationPoint start = routeDraftPoints.get(routeDraftPoints.size() - 1);
        if (meters(start, end) < 1) { showStatus("The route is already at the boarding station."); return; }
        EndpointConfig config = saveConfig(); if (config == null) return;
        JSONArray via = new JSONArray(); via.put(pointJson(start)); via.put(pointJson(end));
        showStatus("Calculating walking path…");
        network.execute(() -> {
            try {
                JSONObject result = ImoveApi.walking(config, via);
                runOnUiThread(() -> {
                    if (routeDraftPoints.isEmpty() || routeDraftPoints.get(routeDraftPoints.size() - 1) != start) {
                        showStatus("The route changed; start the walking calculation again."); return;
                    }
                    appendRoutePoint(end, result.optJSONArray("points"), "Walk · " + station.optString("name"),
                            Math.max(1, Math.min(86400, result.optInt("estimatedSeconds", 300))));
                    renderRouteDraft(); showStatus("Walking segment added.");
                });
            } catch (Exception error) { runOnUiThread(() -> showStatus("Could not get walking path: " + error.getMessage())); }
        });
    }

    private void appendRailSection(JSONObject line, int board, int alight) {
        captureRouteLegFields();
        JSONArray stations = line.optJSONArray("stations");
        if (stations == null || board == alight) { showStatus("Choose different boarding and alighting stations."); return; }
        LocationPoint origin = stationPoint(stations.optJSONObject(board));
        if (!routeDraftPoints.isEmpty()) {
            LocationPoint last = routeDraftPoints.get(routeDraftPoints.size() - 1);
            double gap = meters(last, origin);
            if (gap > 400) { showStatus("The boarding station is far away. Add a walking segment first."); return; }
            if (gap > 1) appendRoutePoint(origin, null, "Transfer · short walk (approximate)",
                    Math.max(60, (int) (gap / 1.2)));
        } else appendRoutePoint(origin, null, "", 0);
        int step = board < alight ? 1 : -1;
        String lineID = line.optString("id");
        for (int index = board; index != alight; index += step) {
            int next = index + step;
            JSONObject source = stations.optJSONObject(Math.min(index, next));
            JSONObject from = stations.optJSONObject(index), to = stations.optJSONObject(next);
            JSONArray shape = source.optJSONArray("pathToNext");
            if (shape == null || shape.length() < 2) { showStatus("Line path missing."); return; }
            JSONArray path = new JSONArray();
            for (int i = 0; i < shape.length(); i++) {
                JSONArray pair = shape.optJSONArray(step > 0 ? i : shape.length() - 1 - i);
                if (pair != null) path.put(pointJson(LocationPoint.parse(Double.toString(pair.optDouble(0)),
                        Double.toString(pair.optDouble(1)))));
            }
            appendRoutePoint(stationPoint(to), path, lineID + " · " + from.optString("name") + " → " +
                    to.optString("name") + (source.optBoolean("geometryApproximate") ? " · approximate path" : ""),
                    "B1".equals(lineID) ? 150 : 120);
        }
        int total = 0; for (int duration : routeLegDurations) total += duration;
        try { routeMinutes.setText(Integer.toString(Math.max(Integer.parseInt(routeMinutes.getText().toString()), (total + 59) / 60))); }
        catch (Exception ignored) { routeMinutes.setText(Integer.toString((total + 59) / 60)); }
        renderRouteDraft(); fitRouteMap();
        showStatus(lineID + " · " + Math.abs(alight - board) + " station segments added. Review the durations.");
    }

    private void chooseLegToEdit() {
        chooseLegToEdit(false);
    }

    private void chooseLegToEdit(boolean calculateAfterSelection) {
        if (routeLegPaths.isEmpty()) { showStatus("Add a route segment first."); return; }
        String[] labels = new String[routeLegPaths.size()];
        for (int i = 0; i < labels.length; i++) labels[i] = (i + 1) + " → " + (i + 2) + " · " + routeLegDescriptions.get(i);
        new AlertDialog.Builder(this).setTitle("Segment to edit")
                .setItems(labels, (dialog, index) -> {
                    editingLegIndex = index; routeMode = true;
                    routeModeButton.setText("Finish drawing route");
                    if (calculateAfterSelection) { calculateSelectedWalk(); return; }
                    if (mapView == null) openMap();
                    showPage("Map"); showStatus("Tap the map to add waypoints to segment " + (index + 1) + ".");
                }).setNegativeButton("Cancel", null).show();
    }

    private void calculateSelectedWalk() {
        int index = editingLegIndex;
        if (index < 0 || index >= routeLegPaths.size()) { chooseLegToEdit(true); return; }
        EndpointConfig config = saveConfig(); if (config == null) return;
        JSONArray via = new JSONArray(); via.put(pointJson(routeDraftPoints.get(index)));
        LocationPoint startPoint = routeDraftPoints.get(index), endPoint = routeDraftPoints.get(index + 1);
        for (LocationPoint point : routeViaPoints.get(index)) via.put(pointJson(point));
        via.put(pointJson(routeDraftPoints.get(index + 1)));
        showStatus("Calculating walking path…");
        network.execute(() -> {
            try {
                JSONObject result = ImoveApi.walking(config, via);
                runOnUiThread(() -> {
                    if (index >= routeLegPaths.size() || routeDraftPoints.get(index) != startPoint ||
                            routeDraftPoints.get(index + 1) != endPoint) {
                        showStatus("The route changed; start the walking calculation again."); return;
                    }
                    routeLegPaths.set(index, result.optJSONArray("points"));
                    routeLegDescriptions.set(index, "Walk · follows streets");
                    routeLegDurations.set(index, Math.max(1, Math.min(86400, result.optInt("estimatedSeconds", 300))));
                    editingLegIndex = -1; renderRouteDraft(); showStatus("Walking path calculated.");
                });
            } catch (Exception error) { runOnUiThread(() -> showStatus("Could not get walking path: " + error.getMessage())); }
        });
    }

    private void renderRouteDraft() {
        if (routeDraftContainer == null) return;
        while (routeLegPaths.size() < routeDraftPoints.size() - 1) {
            int index = routeLegPaths.size();
            routeLegPaths.add(directPath(routeDraftPoints.get(index), routeDraftPoints.get(index + 1)));
            routeLegDescriptions.add("Hand-drawn segment");
            routeViaPoints.add(new ArrayList<>());
        }
        while (routeLegDurations.size() < routeDraftPoints.size() - 1) routeLegDurations.add(300);
        while (routeLegDurations.size() > Math.max(0, routeDraftPoints.size() - 1))
            routeLegDurations.remove(routeLegDurations.size() - 1);
        routeDraftContainer.removeAllViews();
        if (routeDraftPoints.isEmpty()) routeDraftContainer.addView(text("No route points selected yet.", 13, MUTED));
        for (int index = 0; index < routeDraftPoints.size(); index++) {
            LocationPoint point = routeDraftPoints.get(index);
            routeDraftContainer.addView(text((index + 1) + ". " + point.latitude + ", " + point.longitude +
                            (index > 0 ? " · " + routeLegDescriptions.get(index - 1) : ""),
                    12, MUTED));
        }
        renderRouteTiming();
        updateRouteMapOverlay();
    }

    private void captureRouteLegFields() {
        for (int index = 0; index < routeLegDurations.size() && index < routeLegMinuteFields.size(); index++) {
            try {
                int minutes = Integer.parseInt(routeLegMinuteFields.get(index).getText().toString().trim());
                int seconds = Integer.parseInt(routeLegSecondFields.get(index).getText().toString().trim());
                if (minutes >= 0 && seconds >= 0 && seconds <= 59 && minutes <= 1440)
                    routeLegDurations.set(index, minutes * 60 + seconds);
            } catch (NumberFormatException ignored) { /* Validation runs when saving. */ }
        }
    }

    private EditText routeNumber(LinearLayout row, int value) {
        EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_NUMBER);
        input.setSingleLine(true);
        input.setTextSize(15);
        input.setTextColor(TEXT);
        input.setText(Integer.toString(value));
        input.setBackground(round(PANEL_RAISED, 8, LINE));
        row.addView(input, new LinearLayout.LayoutParams(dp(66), dp(44)));
        return input;
    }

    private void renderRouteTiming() {
        if (routeLegFields == null) return;
        routeTimingButton.setText(routeCustomTiming ? "Timing: set each segment separately" : "Timing: split total time evenly");
        routeTotalFields.setVisibility(routeCustomTiming ? android.view.View.GONE : android.view.View.VISIBLE);
        routeLegFields.setVisibility(routeCustomTiming ? android.view.View.VISIBLE : android.view.View.GONE);
        routeLegFields.removeAllViews();
        routeLegMinuteFields.clear();
        routeLegSecondFields.clear();
        if (!routeCustomTiming) return;
        routeLegFields.addView(text("Enter minutes and seconds for each pair of stops.", 13, MUTED));
        for (int index = 0; index < routeLegDurations.size(); index++) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(android.view.Gravity.CENTER_VERTICAL);
            routeLegFields.addView(row);
            row.addView(text((index + 1) + " → " + (index + 2) + "  ", 13, MUTED));
            int duration = routeLegDurations.get(index);
            routeLegMinuteFields.add(routeNumber(row, duration / 60));
            row.addView(text(" dk  ", 13, MUTED));
            routeLegSecondFields.add(routeNumber(row, duration % 60));
            row.addView(text(" sn", 13, MUTED));
        }
    }

    private void updateRouteMapOverlay() {
        if (mapView == null) return;
        JSONArray points = new JSONArray();
        for (LocationPoint point : routeDraftPoints) {
            JSONObject entry = new JSONObject();
            try {
                entry.put("latitude", point.latitude);
                entry.put("longitude", point.longitude);
                points.put(entry);
            } catch (Exception ignored) { return; }
        }
        JSONArray paths = new JSONArray();
        for (JSONArray path : routeLegPaths) paths.put(path);
        mapView.evaluateJavascript("window.postMessage({type:'imove-route-points',points:" +
                points.toString() + ",paths:" + paths.toString() + "},location.origin);", null);
    }

    private void fitRouteMap() {
        if (mapView != null) mapView.evaluateJavascript(
                "window.postMessage({type:'imove-route-fit'},location.origin);", null);
    }

    private void saveRoute() {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        String name = routeName.getText().toString().trim();
        if (routeDraftPoints.size() < 2) { showStatus("Choose at least two route points."); return; }
        int count = routeDraftPoints.size() - 1;
        JSONArray durations = new JSONArray();
        if (routeCustomTiming) {
            if (routeLegMinuteFields.size() != count) { showStatus("Segment durations missing."); return; }
            for (int index = 0; index < count; index++) {
                try {
                    int minutes = Integer.parseInt(routeLegMinuteFields.get(index).getText().toString().trim());
                    int seconds = Integer.parseInt(routeLegSecondFields.get(index).getText().toString().trim());
                    if (minutes < 0 || minutes > 1440 || seconds < 0 || seconds > 59 ||
                            minutes * 60 + seconds < 1 || minutes * 60 + seconds > 86400)
                        throw new NumberFormatException();
                    durations.put(minutes * 60 + seconds);
                } catch (NumberFormatException error) {
                    showStatus((index + 1) + " → " + (index + 2) + " must last between 1 second and 24 hours.");
                    return;
                }
            }
        } else {
            int minutes, seconds;
            try {
                minutes = Integer.parseInt(routeMinutes.getText().toString().trim());
                seconds = Integer.parseInt(routeSeconds.getText().toString().trim());
            } catch (NumberFormatException error) { showStatus("Enter a valid total duration."); return; }
            if (minutes < 0 || minutes > 1440 * count || seconds < 0 || seconds > 59) {
                showStatus("Enter a valid total duration."); return;
            }
            int total = minutes * 60 + seconds;
            if (total < count || total > count * 86400) {
                showStatus("The total duration must give each segment between 1 second and 24 hours."); return;
            }
            int base = total / count, remainder = total % count;
            for (int index = 0; index < count; index++) durations.put(base + (index < remainder ? 1 : 0));
        }
        JSONArray points = new JSONArray();
        for (LocationPoint point : routeDraftPoints) {
            JSONObject entry = new JSONObject();
            try { entry.put("latitude", point.latitude); entry.put("longitude", point.longitude); points.put(entry); }
            catch (Exception error) { showStatus("Could not prepare route points."); return; }
        }
        JSONArray paths = new JSONArray(), descriptions = new JSONArray();
        for (JSONArray path : routeLegPaths) paths.put(path);
        for (String description : routeLegDescriptions) descriptions.put(description);
        showStatus("Saving route…");
        String timingMode = routeCustomTiming ? "custom" : "equal";
        network.execute(() -> {
            try {
                ImoveApi.saveRoute(config, name, timingMode, durations, points, paths, descriptions);
                JSONArray routes = ImoveApi.routes(config).getJSONArray("routes");
                runOnUiThread(() -> {
                    clearRouteDraft();
                    routeName.setText("");
                    routeMode = false;
                    routeModeButton.setText("Start drawing route");
                    renderRouteDraft();
                    renderRoutes(routes);
                    showStatus("Route saved.");
                });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not save route: " + error.getMessage()));
            }
        });
    }

    private void loadRoutes() {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        showStatus("Loading routes…");
        network.execute(() -> {
            try {
                JSONArray routes = ImoveApi.routes(config).getJSONArray("routes");
                runOnUiThread(() -> { renderRoutes(routes); showStatus("Routes refreshed."); });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not load routes: " + error.getMessage()));
            }
        });
    }

    private void renderRoutes(JSONArray routes) {
        routesContainer.removeAllViews();
        if (routes.length() == 0) {
            routesContainer.addView(text("No routes saved yet.", 14, MUTED));
            return;
        }
        for (int index = 0; index < routes.length(); index++) {
            JSONObject route = routes.optJSONObject(index);
            if (route == null) continue;
            String name = route.optString("name");
            String id = route.optString("id");
            String timingMode = route.optString("timingMode", "equal");
            int totalSeconds = route.optInt("totalDurationSeconds", 300);
            JSONArray legSeconds = route.optJSONArray("segmentDurationsSeconds");
            JSONArray points = route.optJSONArray("points");
            if (points == null || points.length() < 2) continue;
            TextView title = text(name + " · " + points.length() + " points · " +
                    ("custom".equals(timingMode) ? "custom" : "even") + " timing · total " + formatRouteDuration(totalSeconds),
                    15, TEXT);
            title.setPadding(0, dp(15), 0, 0);
            routesContainer.addView(title);
            JSONArray paths = route.optJSONArray("segmentPaths");
            JSONArray descriptions = route.optJSONArray("segmentDescriptions");
            button(routesContainer, "Open on map", () -> previewRoute(points, timingMode, totalSeconds,
                    legSeconds, paths, descriptions));
            LinearLayout actions = new LinearLayout(this);
            actions.setOrientation(LinearLayout.HORIZONTAL);
            routesContainer.addView(actions);
            button(actions, "Start", () -> startRoute(id));
            button(actions, "Delete", () -> new AlertDialog.Builder(this)
                    .setTitle("Delete the route \"" + name + "\"?")
                    .setNegativeButton("Cancel", null)
                    .setPositiveButton("Delete", (dialog, which) -> deleteRoute(id)).show());
        }
    }

    private static String formatRouteDuration(int seconds) {
        int hours = seconds / 3600;
        return (hours > 0 ? hours + " sa " : "") + (seconds % 3600 / 60) + " dk " + (seconds % 60) + " sn";
    }

    private void previewRoute(JSONArray points, String timingMode, int totalSeconds, JSONArray durations,
                              JSONArray paths, JSONArray descriptions) {
        clearRouteDraft();
        for (int index = 0; index < points.length(); index++) {
            JSONObject point = points.optJSONObject(index);
            if (point == null) continue;
            try { routeDraftPoints.add(LocationPoint.parse(
                    Double.toString(point.getDouble("latitude")), Double.toString(point.getDouble("longitude")))); }
            catch (Exception ignored) { routeDraftPoints.clear(); showStatus("Could not open route points."); return; }
        }
        routeCustomTiming = "custom".equals(timingMode);
        routeMinutes.setText(Integer.toString(totalSeconds / 60));
        routeSeconds.setText(Integer.toString(totalSeconds % 60));
        if (durations != null) for (int index = 0; index < durations.length(); index++)
            routeLegDurations.add(durations.optInt(index, 300));
        if (paths != null && paths.length() == routeDraftPoints.size() - 1) {
            for (int index = 0; index < paths.length(); index++) {
                routeLegPaths.add(paths.optJSONArray(index));
                routeLegDescriptions.add(descriptions != null ? descriptions.optString(index, "Hand-drawn segment") : "Hand-drawn segment");
                routeViaPoints.add(new ArrayList<>());
            }
        }
        routeName.setText("");
        routeMode = true;
        routeModeButton.setText("Finish drawing route");
        renderRouteDraft();
        if (!routeDraftPoints.isEmpty()) loadMapAt(routeDraftPoints.get(0), false);
        fitRouteMap();
        showStatus("Route opened on the map. Edit it and save it under a new name.");
    }

    private void startRoute(String id) {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        haltTrackingForManual();
        showStatus("Starting route; waiting for the first USB command…");
        network.execute(() -> {
            try {
                String result = ImoveApi.startRoute(config, id).optString("message", "Route started.");
                JSONObject status = ImoveApi.status(config);
                runOnUiThread(() -> { renderActiveRoute(status); showStatus(result); });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not start route: " + error.getMessage()));
            }
        });
    }

    private void stopRoute() {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        showStatus("Stopping route…");
        network.execute(() -> {
            try {
                String result = ImoveApi.stopRoute(config).optString("message", "Route stopped.");
                JSONObject status = ImoveApi.status(config);
                runOnUiThread(() -> { renderActiveRoute(status); showStatus(result); });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not stop route: " + error.getMessage()));
            }
        });
    }

    private void deleteRoute(String id) {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        network.execute(() -> {
            try {
                ImoveApi.deleteRoute(config, id);
                JSONArray routes = ImoveApi.routes(config).getJSONArray("routes");
                runOnUiThread(() -> { renderRoutes(routes); showStatus("Route deleted."); });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not delete route: " + error.getMessage()));
            }
        });
    }

    private void refreshRouteStatus() {
        EndpointConfig config;
        try { config = Settings.load(this); }
        catch (IllegalArgumentException error) { return; }
        network.execute(() -> {
            try {
                JSONObject status = ImoveApi.status(config);
                runOnUiThread(() -> { renderActiveRoute(status); renderRefreshStatus(status); });
            } catch (Exception ignored) { }
        });
    }

    private void renderActiveRoute(JSONObject status) {
        String[] last = status.optString("lastSent", "").split(",");
        if (last.length == 2) {
            try {
                lastSentPoint = LocationPoint.parse(last[0], last[1]);
                if (mapView != null) mapView.evaluateJavascript("window.postMessage({type:'imove-last',latitude:" +
                        lastSentPoint.latitude + ",longitude:" + lastSentPoint.longitude + "},location.origin);", null);
            } catch (IllegalArgumentException ignored) { }
        }
        String name = status.optString("routeName", "");
        if (name.isEmpty()) {
            activeRouteStatus.setText(status.optString("message", "").startsWith("Route completed")
                    ? status.optString("message") : "No active route.");
        } else {
            int percent = (int) Math.round(status.optDouble("routeProgress", 0) * 100);
            activeRouteStatus.setText("Active route: " + name + " · " + percent + "% · segment " +
                    status.optInt("routeSegmentIndex") + "/" + status.optInt("routeSegmentCount"));
        }
    }

    private void renderRefreshStatus(JSONObject status) {
        int seconds = status.optInt("updateIntervalSeconds", 20);
        if (!updateInterval.hasFocus()) updateInterval.setText(Integer.toString(seconds));
        refreshStatus.setText(status.optBoolean("refreshing", false)
                ? "The Mac refreshes the last location at most every " + seconds + " seconds."
                : "Fixed location refresh off · route interval " + seconds + " seconds.");
        if (!status.isNull("lastUSBSetDurationMs")) {
            refreshStatus.append(" Last successful USB command: ~" + status.optInt("lastUSBSetDurationMs") + " ms.");
        }
    }

    private void saveUpdateInterval() {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        int seconds;
        try { seconds = Integer.parseInt(updateInterval.getText().toString().trim()); }
        catch (NumberFormatException error) { showStatus("The interval must be 1–60 seconds."); return; }
        if (seconds < 1 || seconds > 60) { showStatus("The interval must be 1–60 seconds."); return; }
        showStatus("Saving refresh interval…");
        network.execute(() -> {
            try {
                String result = ImoveApi.setUpdateInterval(config, seconds).optString("message", "Interval saved.");
                JSONObject status = ImoveApi.status(config);
                runOnUiThread(() -> { renderRefreshStatus(status); showStatus(result); });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not save interval: " + error.getMessage()));
            }
        });
    }

    private void stopRefresh() {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        network.execute(() -> {
            try {
                String result = ImoveApi.stopRefresh(config).optString("message", "Refresh stopped.");
                JSONObject status = ImoveApi.status(config);
                runOnUiThread(() -> { autoRenew.setChecked(false); renderRefreshStatus(status); showStatus(result); });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not stop refresh: " + error.getMessage()));
            }
        });
    }

    private void savePlace() {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        LocationPoint point;
        try { point = LocationPoint.parse(latitude.getText().toString(), longitude.getText().toString()); }
        catch (IllegalArgumentException error) { showStatus(error.getMessage()); return; }
        String name = placeName.getText().toString().trim();
        if (name.isEmpty() || name.length() > 50) { showStatus("Place names must be 1–50 characters."); return; }
        showStatus("Saving place…");
        network.execute(() -> {
            try {
                ImoveApi.savePlace(config, name, point);
                JSONArray places = ImoveApi.places(config).getJSONArray("places");
                runOnUiThread(() -> {
                    placeName.setText("");
                    renderPlaces(places);
                    showStatus("Place saved.");
                });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not save place: " + error.getMessage()));
            }
        });
    }

    private void loadPlaces() {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        showStatus("Loading saved places…");
        network.execute(() -> {
            try {
                JSONArray places = ImoveApi.places(config).getJSONArray("places");
                runOnUiThread(() -> { renderPlaces(places); showStatus("Saved places refreshed."); });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not load places: " + error.getMessage()));
            }
        });
    }

    private void renderPlaces(JSONArray places) {
        placesContainer.removeAllViews();
        renderQuickPlaces(places);
        if (places.length() == 0) {
            placesContainer.addView(text("No places saved yet.", 14, MUTED));
            return;
        }
        for (int index = 0; index < places.length(); index++) {
            JSONObject place = places.optJSONObject(index);
            if (place == null) continue;
            String name = place.optString("name");
            String id = place.optString("id");
            String lat = Double.toString(place.optDouble("latitude"));
            String lon = Double.toString(place.optDouble("longitude"));
            TextView title = text(name + " · " + lat + ", " + lon, 15, TEXT);
            title.setPadding(0, dp(14), 0, 0);
            placesContainer.addView(title);
            LinearLayout actions = new LinearLayout(this);
            actions.setOrientation(LinearLayout.HORIZONTAL);
            placesContainer.addView(actions);
            button(actions, "Send", () -> {
                EndpointConfig config = saveConfig();
                if (config == null) return;
                try {
                    LocationPoint point = LocationPoint.parse(lat, lon);
                    fill(lat, lon);
                    haltTrackingForManual();
                    send(config, point);
                } catch (IllegalArgumentException error) { showStatus(error.getMessage()); }
            });
            button(actions, "Delete", () -> new AlertDialog.Builder(this)
                    .setTitle("Delete \"" + name + "\"?")
                    .setNegativeButton("Cancel", null)
                    .setPositiveButton("Delete", (dialog, which) -> deletePlace(id))
                    .show());
        }
    }

    private void renderQuickPlaces(JSONArray places) {
        quickPlacesContainer.removeAllViews();
        if (places.length() == 0) {
            quickPlacesContainer.addView(text("No places saved yet.", 13, MUTED));
            return;
        }
        for (int index = 0; index < places.length(); index++) {
            JSONObject place = places.optJSONObject(index);
            if (place == null) continue;
            String name = place.optString("name");
            String lat = Double.toString(place.optDouble("latitude"));
            String lon = Double.toString(place.optDouble("longitude"));
            TextView chip = text(name, 13, ACCENT);
            chip.setTypeface(null, Typeface.BOLD);
            chip.setGravity(Gravity.CENTER);
            chip.setPadding(dp(14), dp(8), dp(14), dp(8));
            chip.setBackground(round(PANEL_RAISED, 10, LINE));
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-2, dp(40));
            params.rightMargin = dp(8);
            quickPlacesContainer.addView(chip, params);
            chip.setOnClickListener(view -> {
                fill(lat, lon);
                showStatus(name + " selected. Press the button below to send it.");
            });
        }
    }

    private void deletePlace(String id) {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        showStatus("Deleting place…");
        network.execute(() -> {
            try {
                ImoveApi.deletePlace(config, id);
                JSONArray places = ImoveApi.places(config).getJSONArray("places");
                runOnUiThread(() -> { renderPlaces(places); showStatus("Place deleted."); });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Could not delete place: " + error.getMessage()));
            }
        });
    }

    private void sendEntered() {
        EndpointConfig config = saveConfig();
        if (config == null) return;
        LocationPoint point;
        try { point = LocationPoint.parse(latitude.getText().toString(), longitude.getText().toString()); }
        catch (IllegalArgumentException error) { showStatus(error.getMessage()); return; }
        haltTrackingForManual();
        send(config, point);
    }

    private void sendCurrent() {
        if (saveConfig() == null) return;
        haltTrackingForManual();
        waitingForCurrent = true;
        if (!hasFineLocation()) {
            askLocation();
            return;
        }
        collectCurrent();
    }

    private void collectCurrent() {
        waitingForCurrent = false;
        showStatus("Getting the phone's location…");
        LocationProbe.once(this, location -> {
            fill(Double.toString(location.getLatitude()), Double.toString(location.getLongitude()));
            EndpointConfig config = saveConfig();
            if (config != null) send(config, LocationPoint.parse(latitude.getText().toString(), longitude.getText().toString()));
        }, this::showStatus);
    }

    private void send(EndpointConfig config, LocationPoint point) {
        boolean renew = autoRenew.isChecked();
        showStatus("Contacting the Mac…");
        network.execute(() -> {
            try {
                String result = ImoveApi.send(config, point, renew).optString("message", "Location sent.");
                JSONObject status = ImoveApi.status(config);
                runOnUiThread(() -> { lastSentPoint = point; renderRefreshStatus(status); showStatus(result); });
            } catch (Exception error) {
                runOnUiThread(() -> showStatus("Operation failed: " + error.getMessage()));
            }
        });
    }

    private void startTracking() {
        if (saveConfig() == null) return;
        if (TrackingService.running) { showStatus("The 5-minute relay is already on."); return; }
        waitingToTrack = true;
        if (!hasFineLocation()) { askLocation(); return; }
        askNotificationOrStart();
    }

    private void askNotificationOrStart() {
        if (Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQUEST_NOTIFICATION);
        } else {
            beginTracking();
        }
    }

    private void beginTracking() {
        waitingToTrack = false;
        Intent start = new Intent(this, TrackingService.class).setAction(TrackingService.ACTION_START);
        try {
            startForegroundService(start);
            showStatus("Starting the 5-minute relay. You can follow it in the notification.");
            trackingStatus.setText(R.string.tracking_starting);
        } catch (RuntimeException error) {
            showStatus("Could not start relay: " + error.getMessage());
        }
    }

    private void stopTracking() {
        haltTrackingForManual();
        showStatus("5-minute relay stopped.");
    }

    private void haltTrackingForManual() {
        stopService(new Intent(this, TrackingService.class));
        trackingStatus.setText(R.string.tracking_off);
    }

    private void confirmClear() {
        new AlertDialog.Builder(this)
                .setTitle("Remove the simulated location?")
                .setMessage("The iPhone may return to its real location. An active relay will be stopped.")
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Remove", (dialog, which) -> {
                    EndpointConfig config = saveConfig();
                    if (config == null) return;
                    haltTrackingForManual();
                    runNetwork(() -> ImoveApi.clear(config).optString("message", "Clear command sent."));
                }).show();
    }

    private EndpointConfig saveConfig() {
        try {
            EndpointConfig config = EndpointConfig.parse(address.getText().toString(), code.getText().toString());
            Settings.save(this, config);
            return config;
        } catch (RuntimeException error) {
            showStatus(error.getMessage());
            return null;
        }
    }

    private boolean hasFineLocation() {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private void askLocation() {
        requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, REQUEST_LOCATION);
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grants) {
        super.onRequestPermissionsResult(requestCode, permissions, grants);
        if (requestCode == REQUEST_LOCATION) {
            if (!hasFineLocation()) {
                waitingToTrack = false;
                waitingForCurrent = false;
                waitingForMap = false;
                showStatus("Precise location permission was not granted, so the phone's location cannot be sent.");
            } else if (waitingToTrack) askNotificationOrStart();
            else if (waitingForCurrent) collectCurrent();
            else if (waitingForMap) collectMapCurrent();
        } else if (requestCode == REQUEST_NOTIFICATION && waitingToTrack) {
            if (Build.VERSION.SDK_INT < 33 ||
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                beginTracking();
            } else {
                waitingToTrack = false;
                showStatus("Allow notifications to show the tracking notification.");
            }
        }
    }

    private interface NetworkAction { String run() throws Exception; }

    private void runNetwork(NetworkAction action) {
        showStatus("Contacting the Mac…");
        network.execute(() -> {
            String result;
            try { result = action.run(); }
            catch (Exception error) { result = "Operation failed: " + error.getMessage(); }
            String finalResult = result;
            runOnUiThread(() -> showStatus(finalResult));
        });
    }

    private void showStatus(String text) {
        if (message != null) message.setText(text);
    }

    private void fill(String lat, String lon) {
        latitude.setText(lat);
        longitude.setText(lon);
    }

    private void heading(LinearLayout parent, String value) {
        TextView view = text(value, 20, TEXT);
        view.setTypeface(null, Typeface.BOLD);
        view.setPadding(0, 0, 0, dp(12));
        parent.addView(view);
    }

    private LinearLayout card(LinearLayout parent) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(18), dp(20), dp(18), dp(18));
        card.setBackground(round(PANEL, 18, LINE));
        card.setElevation(dp(2));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.bottomMargin = dp(14);
        parent.addView(card, params);
        return card;
    }

    private GradientDrawable round(int fill, int radiusDp, int stroke) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(fill);
        drawable.setCornerRadius(dp(radiusDp));
        if (stroke != 0) drawable.setStroke(dp(1), stroke);
        return drawable;
    }

    private EditText field(LinearLayout parent, String label, String hint, boolean secret) {
        TextView title = text(label, 13, MUTED);
        title.setPadding(0, dp(12), 0, 0);
        parent.addView(title);
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setTextSize(16);
        input.setHint(hint);
        input.setTextColor(TEXT);
        input.setHintTextColor(MUTED);
        input.setInputType(secret ? InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD
                : InputType.TYPE_CLASS_TEXT);
        input.setPadding(dp(13), 0, dp(13), 0);
        input.setBackground(round(PANEL_RAISED, 10, LINE));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, dp(52));
        params.bottomMargin = dp(8);
        parent.addView(input, params);
        return input;
    }

    private Button button(LinearLayout parent, String title, Runnable action) {
        Button button = new Button(this);
        button.setText(title);
        button.setAllCaps(false);
        String lower = title.toLowerCase(java.util.Locale.ROOT);
        boolean primary = lower.contains("send") || lower.contains("start") || lower.contains("save") || lower.contains("sign in");
        button.setTextColor(primary ? BG : TEXT);
        button.setTypeface(null, Typeface.BOLD);
        button.setBackground(round(primary ? ACCENT : PANEL_RAISED, 10, primary ? 0 : LINE));
        button.setMinHeight(dp(46));
        button.setOnClickListener(view -> action.run());
        LinearLayout.LayoutParams params = parent.getOrientation() == LinearLayout.HORIZONTAL
                ? new LinearLayout.LayoutParams(0, dp(46), 1)
                : new LinearLayout.LayoutParams(-1, dp(46));
        params.bottomMargin = dp(8);
        if (parent.getOrientation() == LinearLayout.HORIZONTAL) params.rightMargin = dp(7);
        parent.addView(button, params);
        return button;
    }

    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        return view;
    }

    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density + 0.5f); }

    @Override protected void onDestroy() {
        routeHandler.removeCallbacks(routePoll);
        if (mapDialog != null) mapDialog.dismiss();
        if (mapView != null) { mapContainer.removeView(mapView); mapView.destroy(); mapView = null; }
        network.shutdownNow();
        super.onDestroy();
    }
}
