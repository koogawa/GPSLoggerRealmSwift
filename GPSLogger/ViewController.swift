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
    dynamic var latitude:Double = 0
    dynamic var longitude:Double = 0
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
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100

        // Delete old location objects
        deleteOldLocations()

        // Load saved location objects
        locations = loadSavedLocations()

        // Drop pins
        for location: Location in locations {
            dropPin(location)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


    // MARK: - Private methods

    @IBAction func startButtonDidTap(_ sender: AnyObject) {
        let realm = try! Realm()
        if isUpdating == true {
            // Stop
            isUpdating = false
            locationManager.stopUpdatingLocation()
            startButton.setTitle("Start", for: UIControlState())
            // Remove a previously registered notification
            if token != nil {
                token.stop()
            }
        }
        else {
            // Start
            isUpdating = true
            locationManager.startUpdatingLocation()
            startButton.setTitle("Stop", for: UIControlState())
            // Add a notification handler for changes
            token = realm.addNotificationBlock {
                [weak self] notification, realm in
                self?.tableView.reloadData()
            }
        }
    }

    @IBAction func clearButtonDidTap(_ sender: AnyObject) {
        deleteAllLocations()
        locations = loadSavedLocations()
        removeAllAnnotations()
        self.tableView.reloadData()
    }

    // Load locations saved in realm at the table view
    fileprivate func loadSavedLocations() -> Results<Location> {
        // Get the default Realm
        let realm = try! Realm()

        // Load recent location objects
        return realm.objects(Location.self).sorted(byKeyPath: "createdAt", ascending: false)
    }

    // Save object in a background thread
    fileprivate func addCurrentLocation(_ rowLocation: CLLocation) {
        let location = makeLocation(rowLocation)
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
            realm.beginWrite()
            // Delete old Location objects
            let oldLocations = realm.objects(Location.self).filter(NSPredicate(format:"createdAt < %@", NSDate().addingTimeInterval(-86400)))
            realm.delete(oldLocations)
            try! realm.commitWrite()
        }
    }

    // Delete all location objects from realm
    fileprivate func deleteAllLocations() {
        // Get the default Realm
        let realm = try! Realm()
        realm.beginWrite()
        // Delete all Location objects
        realm.deleteAll()
        try! realm.commitWrite()
    }

    // Make Location object from CLLocation
    fileprivate func makeLocation(_ rawLocation: CLLocation) -> Location {
        let location = Location()
        location.latitude = rawLocation.coordinate.latitude
        location.longitude = rawLocation.coordinate.longitude
        location.createdAt = Date()
        return location
    }

    // Drop pin on the map
    fileprivate func dropPin(_ location: Location) {
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
        let annotations = mapView.annotations.filter {
            $0 !== self.mapView.userLocation
        }
        mapView.removeAnnotations(annotations)
    }

    // MARK: - CLLocationManager delegate

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == CLAuthorizationStatus.notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        else if status == CLAuthorizationStatus.authorizedAlways {
            // Center user location on the map
            let span = MKCoordinateSpanMake(0.003, 0.003)
            let region = MKCoordinateRegionMake(mapView.userLocation.coordinate, span)
            mapView.setRegion(region, animated:true)
            mapView.userTrackingMode = MKUserTrackingMode.followWithHeading
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations:[CLLocation]) {
        guard let newLocation = locations.last else {
            return
        }

        if !CLLocationCoordinate2DIsValid(newLocation.coordinate) {
            return
        }

        addCurrentLocation(newLocation)

        let location = makeLocation(newLocation)
        dropPin(location)
    }


    // MARK: - MKMapView delegate

    func mapView(_ mapView: MKMapView!, viewForAnnotation annotation: MKAnnotation!) -> MKAnnotationView! {

        if annotation is MKUserLocation {
            return nil
        }

        let reuseId = "annotationIdentifier"

        var pinView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) as? MKPinAnnotationView
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

