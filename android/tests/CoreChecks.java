package com.imove.android;

public final class CoreChecks {
    private static int passed;

    public static void main(String[] args) {
        EndpointConfig valid = EndpointConfig.parse(" https://mini.example.ts.net/ ",
                "AABBCCDDEEFF00112233445566778899");
        check("https://mini.example.ts.net".equals(valid.baseUrl), "HTTPS URL normalization");
        check("aabbccddeeff00112233445566778899".equals(valid.token), "Pairing code normalization");
        invalid(() -> EndpointConfig.parse("http://mini.example.ts.net", valid.token));
        invalid(() -> EndpointConfig.parse("https://mini.example.ts.net.evil.com", valid.token));
        invalid(() -> EndpointConfig.parse("https://mini.example.ts.net/other", valid.token));
        invalid(() -> EndpointConfig.parse("https://mini.example.ts.net/?code=x", valid.token));
        invalid(() -> EndpointConfig.parse("https://mini.example.ts.net", "1234"));
        LocationPoint point = LocationPoint.parse("41,0082", "28.9784");
        check(point.latitude == 41.0082 && point.longitude == 28.9784, "Coordinate parsing");
        invalid(() -> LocationPoint.parse("91", "0"));
        invalid(() -> LocationPoint.parse("NaN", "0"));
        System.out.println("Android core checks: " + passed + " passed");
    }

    private static void invalid(Runnable action) {
        try { action.run(); throw new AssertionError("Invalid input was accepted"); }
        catch (IllegalArgumentException expected) { passed++; }
    }

    private static void check(boolean condition, String label) {
        if (!condition) throw new AssertionError(label);
        passed++;
    }
}
