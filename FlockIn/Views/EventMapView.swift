import SwiftUI
import MapKit

struct EventMapView: UIViewRepresentable {
    let eventCoordinate: CLLocationCoordinate2D
    let userLocation: CLLocation?
    private let radius: Double = 200

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.mapType = .standard

        let region = MKCoordinateRegion(
            center: eventCoordinate,
            latitudinalMeters: 700,
            longitudinalMeters: 700
        )
        mapView.setRegion(region, animated: false)

        let annotation = MKPointAnnotation()
        annotation.coordinate = eventCoordinate
        mapView.addAnnotation(annotation)

        let circle = MKCircle(center: eventCoordinate, radius: radius)
        mapView.addOverlay(circle)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor(red: 0.259, green: 0.522, blue: 0.957, alpha: 0.12)
                renderer.strokeColor = UIColor(red: 0.259, green: 0.522, blue: 0.957, alpha: 0.5)
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "event")
            view.markerTintColor = .systemRed
            return view
        }
    }
}
