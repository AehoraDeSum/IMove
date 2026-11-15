import MapKit
import SwiftUI

struct MapCanvas: UIViewRepresentable {
    var selected: Point?
    var sent: Point?
    var device: Point?
    var routePoints: [Point] = []
    var routePaths: [[Point]] = []
    var onPick: ((Point) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.mapType = .mutedStandard
        view.pointOfInterestFilter = .excludingAll
        view.showsCompass = true
        view.showsScale = true
        view.overrideUserInterfaceStyle = .dark
        let gesture = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.tapped(_:)))
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        view.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784),
                                          span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)), animated: false)
        return view
    }

    func updateUIView(_ view: MKMapView, context: Context) {
        context.coordinator.parent = self
        let key = ([selected, sent, device].compactMap { $0?.label } +
                   routePoints.map(\.label) + routePaths.flatMap { $0.map(\.label) }).joined(separator: ";")
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key
        view.removeAnnotations(view.annotations)
        view.removeOverlays(view.overlays)
        func pin(_ point: Point?, _ title: String) {
            guard let point else { return }
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            annotation.title = title
            view.addAnnotation(annotation)
        }
        pin(selected, "Selected")
        pin(sent, "Sent")
        pin(device, "This device")
        for (index, point) in routePoints.enumerated() { pin(point, "Stop \(index + 1)") }
        let paths = routePaths.isEmpty ? zip(routePoints, routePoints.dropFirst()).map { [$0.0, $0.1] } : routePaths
        for path in paths where path.count >= 2 {
            let coordinates = path.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            view.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
        }
        let focus = selected ?? routePoints.last ?? sent ?? device
        if let focus {
            let center = CLLocationCoordinate2D(latitude: focus.latitude, longitude: focus.longitude)
            if abs(view.region.center.latitude - center.latitude) > max(0.004, view.region.span.latitudeDelta * 0.35) ||
               abs(view.region.center.longitude - center.longitude) > max(0.004, view.region.span.longitudeDelta * 0.35) {
                view.setRegion(MKCoordinateRegion(center: center,
                                                  span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)), animated: true)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapCanvas
        var lastKey = ""
        init(_ parent: MapCanvas) { self.parent = parent }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let view = recognizer.view as? MKMapView else { return }
            let coordinate = view.convert(recognizer.location(in: view), toCoordinateFrom: view)
            let point = Point(coordinate.latitude, coordinate.longitude)
            if point.isValid { parent.onPick?(point) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor(red: 0.31, green: 0.86, blue: 0.55, alpha: 1)
            renderer.lineWidth = 5
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            switch annotation.title ?? "" {
            case "Sent": view.markerTintColor = .systemGreen
            case "This device": view.markerTintColor = .systemBlue
            case "Selected": view.markerTintColor = .systemYellow
            default: view.markerTintColor = .systemMint
            }
            view.canShowCallout = true
            return view
        }
    }
}
