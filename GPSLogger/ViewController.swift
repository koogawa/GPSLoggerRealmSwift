//
//  ViewController.swift
//  GPSLogger
//
//  Created by koogawa on 2015/08/01.
//  Copyright (c) 2015 Kosuke Ogawa. All rights reserved.
//

import UIKit
import MapKit
import RealmSwift

class Location: Object {
    dynamic var latitude: Double = 0.0
    dynamic var longitude: Double = 0.0
    dynamic var createdAt = Date(timeIntervalSince1970: 1)
}

class ViewController: UIViewController, CLLocationManagerDelegate {

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var tableView: UITableView!

    var locationManager: CLLocationManager!
    var locations: Results<Location>!
    var token: NotificationToken!
    var isUpdating = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view, typically from a nib.
        self.locationManager = CLLocationManager()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.distanceFilter = 100

        // Delete old location objects
        self.deleteOldLocations()

        // Load saved location objects
        self.locations = self.loadSavedLocations()

        // Drop pins
        for location in self.locations {
            dropPin(at: location)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


    // MARK: - Private methods

    @IBAction func startButtonDidTap(_ sender: AnyObject) {
        self.toggleLocationUpdate()
    }

    @IBAction func clearButtonDidTap(_ sender: AnyObject) {
        deleteAllLocations()
        locations = loadSavedLocations()
        removeAllAnnotations()
        self.tableView.reloadData()
    }

    // Load locations stored in realm at the table view
    fileprivate func loadSavedLocations() -> Results<Location> {
        // Get the default Realm
        let realm = try! Realm()

        // Load recent location objects
        return realm.objects(Location.self).sorted(byKeyPath: "createdAt", ascending: false)
    }

    // Start or Stop location update
    fileprivate func toggleLocationUpdate() {
        let realm = try! Realm()
        if self.isUpdating {
            // Stop
            self.isUpdating = false
            self.locationManager.stopUpdatingLocation()
            self.startButton.setTitle("Start", for: UIControlState())

            // Remove a previously registered notification
            if let token = self.token {
                token.stop()
            }
        } else {
            // Start
            self.isUpdating = true
            self.locationManager.startUpdatingLocation()
            self.startButton.setTitle("Stop", for: UIControlState())

            // Add a notification handler for changes
            self.token = realm.addNotificationBlock {
                [weak self] notification, realm in
                self?.tableView.reloadData()
            }
        }
    }

    // Save object in a background thread
    fileprivate func addCurrentLocation(_ rowLocation: CLLocation) {
        let location = makeLocation(rawLocation: rowLocation)
        DispatchQueue.main.async {
            // Get the default Realm
            let realm = try! Realm()
            realm.beginWrite()
            // Create a Location object
            realm.add(location)
            try! realm.commitWrite()
        }
    }

    // Delete old (-1 day) objects in a background thread
    fileprivate func deleteOldLocations() {
        DispatchQueue.main.async {
            // Get the default Realm
            let realm = try! Realm()

            // Old Locations stored in Realm
            let oldLocations = realm.objects(Location.self).filter(NSPredicate(format:"createdAt < %@", NSDate().addingTimeInterval(-86400)))

            // Delete an object with a transaction
            try! realm.write {
                realm.delete(oldLocations)
            }
        }
    }

    // Delete all location objects from realm
    fileprivate func deleteAllLocations() {
        // Get the default Realm
        let realm = try! Realm()

        // Delete all objects from the realm
        try! realm.write {
            realm.deleteAll()
        }
    }

    // Make Location object from CLLocation
    fileprivate func makeLocation(rawLocation: CLLocation) -> Location {
        let location = Location()
        location.latitude = rawLocation.coordinate.latitude
        location.longitude = rawLocation.coordinate.longitude
        location.createdAt = Date()
        return location
    }

    // Drop pin on the map
    fileprivate func dropPin(at location: Location) {
        if location.latitude != 0 && location.longitude != 0 {
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2DMake(location.latitude, location.longitude)
            annotation.title = "\(location.latitude),\(location.longitude)"
            annotation.subtitle = location.createdAt.description

            DispatchQueue.main.async(execute: {
                self.mapView.addAnnotation(annotation)
            })
        }
    }

    // Remove all pins on the map
    fileprivate func removeAllAnnotations() {
        let annotations = self.mapView.annotations.filter {
            $0 !== self.mapView.userLocation
        }
        self.mapView.removeAnnotations(annotations)
    }

    // MARK: - CLLocationManager delegate

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == CLAuthorizationStatus.notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        else if status == CLAuthorizationStatus.authorizedAlways {
            // Center user location on the map
            let span = MKCoordinateSpanMake(0.003, 0.003)
            let region = MKCoordinateRegionMake(self.mapView.userLocation.coordinate, span)
            self.mapView.setRegion(region, animated:true)
            self.mapView.userTrackingMode = MKUserTrackingMode.followWithHeading
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations:[CLLocation]) {
        guard let newLocation = locations.last else {
            return
        }

        if !CLLocationCoordinate2DIsValid(newLocation.coordinate) {
            return
        }

        self.addCurrentLocation(newLocation)

        let location = makeLocation(rawLocation: newLocation)
        dropPin(at: location)
    }


    // MARK: - MKMapView delegate

    func mapView(_ mapView: MKMapView!, viewForAnnotation annotation: MKAnnotation!) -> MKAnnotationView! {

        if annotation is MKUserLocation {
            return nil
        }

        let reuseId = "annotationIdentifier"

        var pinView = self.mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) as? MKPinAnnotationView
        if pinView == nil {
            pinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: reuseId)
            pinView?.canShowCallout = true
            pinView?.animatesDrop = true
        }
        else {
            pinView?.annotation = annotation
        }

        return pinView
    }


    // MARK: - Table view data source

    func numberOfSectionsInTableView(_ tableView: UITableView) -> Int {
        // Return the number of sections.
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Return the number of rows in the section.
        return locations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAtIndexPath indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CellIdentifier", for: indexPath) 

        let location = locations[indexPath.row]
        cell.textLabel?.text = "\(location.latitude),\(location.longitude)"
        cell.detailTextLabel?.text = location.createdAt.description

        return cell
    }


    // MARK: - Table view delegate

    func tableView(_ tableView: UITableView, didSelectRowAtIndexPath indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

