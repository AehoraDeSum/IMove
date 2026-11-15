package com.imove.android;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.Locale;

final class EndpointConfig {
    final String baseUrl;
    final String token;

    private EndpointConfig(String baseUrl, String token) {
        this.baseUrl = baseUrl;
        this.token = token;
    }

    static EndpointConfig parse(String enteredUrl, String enteredToken) {
        String raw = enteredUrl == null ? "" : enteredUrl.trim();
        String code = enteredToken == null ? "" : enteredToken.trim().toLowerCase(Locale.ROOT);
        if (!code.matches("[0-9a-f]{32}")) {
            throw new IllegalArgumentException("Enter the 32-character pairing code from the Mac.");
        }
        try {
            URI uri = new URI(raw);
            String host = uri.getHost();
            if (!"https".equalsIgnoreCase(uri.getScheme()) || host == null ||
                    !host.toLowerCase(Locale.ROOT).endsWith(".ts.net") ||
                    host.length() <= ".ts.net".length() || uri.getPort() != -1 ||
                    uri.getRawUserInfo() != null || uri.getRawQuery() != null ||
                    uri.getRawFragment() != null ||
                    !(uri.getRawPath() == null || uri.getRawPath().isEmpty() || "/".equals(uri.getRawPath()))) {
                throw new IllegalArgumentException("Enter the https://…ts.net address from Tailscale.");
            }
            return new EndpointConfig("https://" + host.toLowerCase(Locale.ROOT), code);
        } catch (URISyntaxException error) {
            throw new IllegalArgumentException("The HTTPS address is not valid.");
        }
    }
}
