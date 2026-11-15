package com.imove.android;

final class LocationPoint {
    final double latitude;
    final double longitude;

    private LocationPoint(double latitude, double longitude) {
        this.latitude = latitude;
        this.longitude = longitude;
    }

    static LocationPoint parse(String latitude, String longitude) {
        try {
            double lat = Double.parseDouble(latitude.trim().replace(',', '.'));
            double lon = Double.parseDouble(longitude.trim().replace(',', '.'));
            if (!Double.isFinite(lat) || !Double.isFinite(lon) ||
                    lat < -90 || lat > 90 || lon < -180 || lon > 180) {
                throw new NumberFormatException();
            }
            return new LocationPoint(lat, lon);
        } catch (RuntimeException error) {
            throw new IllegalArgumentException("Latitude must be within −90…90 and longitude within −180…180.");
        }
    }
}
