package com.imove.android;

import org.json.JSONException;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

final class ImoveApi {
    private ImoveApi() {}

    static JSONObject status(EndpointConfig config) throws Exception {
        return request(config, "GET", "/api/status", null);
    }

    static JSONObject send(EndpointConfig config, LocationPoint point) throws Exception {
        return send(config, point, false);
    }

    static JSONObject send(EndpointConfig config, LocationPoint point, boolean renew) throws Exception {
        JSONObject body = new JSONObject();
        body.put("latitude", Double.toString(point.latitude));
        body.put("longitude", Double.toString(point.longitude));
        body.put("renew", renew);
        return request(config, "POST", "/api/location", body);
    }

    static JSONObject setUpdateInterval(EndpointConfig config, int seconds) throws Exception {
        JSONObject body = new JSONObject();
        body.put("seconds", seconds);
        return request(config, "POST", "/api/settings/interval", body);
    }

    static JSONObject stopRefresh(EndpointConfig config) throws Exception {
        return request(config, "POST", "/api/refresh/stop", new JSONObject());
    }

    static JSONObject sendTracking(EndpointConfig config, LocationPoint point) throws Exception {
        JSONObject body = new JSONObject();
        body.put("latitude", Double.toString(point.latitude));
        body.put("longitude", Double.toString(point.longitude));
        return request(config, "POST", "/api/location", body, true);
    }

    static JSONObject activateTracking(EndpointConfig config) throws Exception {
        return request(config, "POST", "/api/tracking/activate", new JSONObject());
    }

    static JSONObject clear(EndpointConfig config) throws Exception {
        return request(config, "POST", "/api/clear", new JSONObject());
    }

    static JSONObject places(EndpointConfig config) throws Exception {
        return request(config, "GET", "/api/places", null);
    }

    static JSONObject savePlace(EndpointConfig config, String name, LocationPoint point) throws Exception {
        JSONObject body = new JSONObject();
        body.put("name", name);
        body.put("latitude", Double.toString(point.latitude));
        body.put("longitude", Double.toString(point.longitude));
        return request(config, "POST", "/api/places", body);
    }

    static JSONObject deletePlace(EndpointConfig config, String id) throws Exception {
        JSONObject body = new JSONObject();
        body.put("id", id);
        return request(config, "POST", "/api/places/delete", body);
    }

    static JSONObject routes(EndpointConfig config) throws Exception {
        return request(config, "GET", "/api/routes", null);
    }

    static JSONObject transit(EndpointConfig config) throws Exception {
        return request(config, "GET", "/api/transit", null);
    }

    static JSONObject walking(EndpointConfig config, JSONArray points) throws Exception {
        JSONObject body = new JSONObject();
        body.put("points", points);
        return request(config, "POST", "/api/route/walking", body);
    }

    static JSONObject saveRoute(EndpointConfig config, String name, String timingMode,
                                JSONArray segmentDurationsSeconds, JSONArray points,
                                JSONArray segmentPaths, JSONArray segmentDescriptions) throws Exception {
        JSONObject body = new JSONObject();
        body.put("name", name);
        body.put("timingMode", timingMode);
        body.put("segmentDurationsSeconds", segmentDurationsSeconds);
        body.put("points", points);
        body.put("segmentPaths", segmentPaths);
        body.put("segmentDescriptions", segmentDescriptions);
        return request(config, "POST", "/api/routes", body);
    }

    static JSONObject deleteRoute(EndpointConfig config, String id) throws Exception {
        JSONObject body = new JSONObject();
        body.put("id", id);
        return request(config, "POST", "/api/routes/delete", body);
    }

    static JSONObject startRoute(EndpointConfig config, String id) throws Exception {
        JSONObject body = new JSONObject();
        body.put("id", id);
        return request(config, "POST", "/api/routes/start", body);
    }

    static JSONObject stopRoute(EndpointConfig config) throws Exception {
        return request(config, "POST", "/api/routes/stop", new JSONObject());
    }

    private static JSONObject request(EndpointConfig config, String method, String path, JSONObject body) throws Exception {
        return request(config, method, path, body, false);
    }

    private static JSONObject request(EndpointConfig config, String method, String path, JSONObject body,
                                      boolean tracking) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(config.baseUrl + path).openConnection();
        try {
            connection.setRequestMethod(method);
            connection.setConnectTimeout(12000);
            connection.setReadTimeout(25000);
            connection.setUseCaches(false);
            connection.setRequestProperty("X-IMove-Token", config.token);
            if (tracking) connection.setRequestProperty("X-IMove-Source", "tracking");
            connection.setRequestProperty("Accept", "application/json");
            if (body != null) {
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json");
                byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
                connection.setFixedLengthStreamingMode(bytes.length);
                try (OutputStream out = connection.getOutputStream()) { out.write(bytes); }
            }
            int status = connection.getResponseCode();
            InputStream input = status < 400 ? connection.getInputStream() : connection.getErrorStream();
            String payload = readBounded(input);
            JSONObject response;
            try { response = new JSONObject(payload); }
            catch (JSONException error) { throw new Exception("The Mac returned an unreadable response."); }
            if (status >= 400 || !response.optBoolean("ok", false)) {
                throw new Exception(response.optString("message", "The Mac could not complete the operation."));
            }
            return response;
        } finally {
            connection.disconnect();
        }
    }

    private static String readBounded(InputStream input) throws Exception {
        if (input == null) return "";
        try (InputStream stream = input; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] chunk = new byte[1024];
            int total = 0;
            int count;
            while ((count = stream.read(chunk)) != -1) {
                total += count;
                if (total > 8_000_000) throw new Exception("The Mac response is larger than expected.");
                out.write(chunk, 0, count);
            }
            return out.toString("UTF-8");
        }
    }
}
