import 'package:flutter/material.dart';
import 'package:google_geofence_helper/google_geofence_helper.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:convert';

class ControllerExample extends StatefulWidget {
  const ControllerExample({super.key});

  @override
  State<ControllerExample> createState() => _ControllerExampleState();
}

class _ControllerExampleState extends State<ControllerExample> {
  // Using both ways to get the controller for demonstration
  final _mapKey = GlobalKey<InteractiveMapGeofenceState>();
  InteractiveMapGeofenceController? _controller;
  String _polygonStatus = "No polygon created";
  String _geofenceDataJson = "{}";
  bool _isEditMode = false;
  bool _isSatelliteMode = false;
  String _controllerSource = "Not initialized";
  
  // Sample saved polygon data around Victoria train station, London
  final Map<String, dynamic> _victoriaStationPolygon = {
    'status': 'finalized',
    'message': 'Polygon has been finalized.',
    'isComplete': true,
    'isFinalized': true,
    'inEditMode': true, // We'll load it in edit mode
    'pointCount': 5,
    'polygon': [
      {'latitude': 51.4965, 'longitude': -0.1447},
      {'latitude': 51.4958, 'longitude': -0.1423},
      {'latitude': 51.4944, 'longitude': -0.1426},
      {'latitude': 51.4942, 'longitude': -0.1449},
      {'latitude': 51.4958, 'longitude': -0.1456}
    ]
  };

  @override
  void initState() {
    super.initState();
  }

  void _updateGeofenceData() {
    if (_controller == null) return;
    
    setState(() {
      // Get the full geofence data and format as JSON
      final geofenceData = _controller!.getGeofenceData();
      _geofenceDataJson = JsonEncoder.withIndent('  ').convert(geofenceData);
      
      // Update status information
      final status = geofenceData['status'] as String;
      final message = geofenceData['message'] as String;
      _polygonStatus = "$status: $message";
      
      // Update UI state
      _isEditMode = _controller!.isInEditMode;
    });
  }
  
  void _loadSavedPolygon() {
    if (_controller == null) return;
    
    // Load the predefined Victoria station polygon
    final success = _controller!.loadGeofenceData(_victoriaStationPolygon);
    
    if (success) {
      setState(() {
        // Update the view camera to Victoria station
        _moveCameraToVictoriaStation();
        
        // Update the UI to reflect changes
        _updateGeofenceData();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully loaded Victoria station polygon in edit mode'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load the saved polygon'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _moveCameraToVictoriaStation() async {
    // Use the controller's moveCamera method instead of accessing private fields
    if (_controller != null) {
      await _controller!.moveCamera(
        const LatLng(51.4953, -0.1437), // Victoria station coordinates
        zoom: 16.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controller API Example'),
      ),
      body: Column(
        children: [
          // Controller source indicator
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.blue[100],
            width: double.infinity,
            child: Text(
              'Controller source: $_controllerSource',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          // Custom Controls Bar
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[200],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(_isSatelliteMode ? Icons.map : Icons.satellite),
                  onPressed: () {
                    if (_controller != null) {
                      _controller!.toggleMapType();
                      setState(() {
                        _isSatelliteMode = !_isSatelliteMode;
                      });
                    }
                  },
                  tooltip: 'Toggle Map Type',
                ),
                IconButton(
                  icon: Icon(_isEditMode ? Icons.check : Icons.edit),
                  onPressed: () {
                    if (_controller != null) {
                      _controller!.toggleEditMode();
                      _updateGeofenceData();
                    }
                  },
                  tooltip: 'Toggle Edit Mode',
                ),
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: _controller?.isPolygonStarted == true
                      ? () {
                          _controller?.deleteLastVertex();
                          _updateGeofenceData();
                        }
                      : null,
                  tooltip: 'Undo Last Point',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _controller?.isPolygonStarted == true
                      ? () {
                          _controller?.clearPolygon();
                          _updateGeofenceData();
                        }
                      : null,
                  tooltip: 'Clear All Points',
                ),
                // Load saved polygon button
                IconButton(
                  icon: const Icon(Icons.restore),
                  onPressed: () => _loadSavedPolygon(),
                  tooltip: 'Load Victoria Station Polygon',
                ),
              ],
            ),
          ),
          // Map
          Expanded(
            flex: 2,
            child: InteractiveMapGeofence(
              key: _mapKey,
              initialPosition: const LatLng(51.5074, -0.1278), // London
              initialZoom: 13,
              markerColor: Colors.blue,
              polygonOpacity: 0.3,
              strokeWidth: 2,
              enableTilt: true,
              enableRotate: true,
              enableCompass: true,
              minZoom: 3,
              maxZoom: 22,
              showControls: false, // Hide built-in controls
              onPolygonUpdated: (points) {
                // Update UI when polygon changes
                _updateGeofenceData();
              },
              onControllerCreated: (controller) {
                setState(() {
                  _controller = controller;
                  _controllerSource = "onControllerCreated callback";
                  _updateGeofenceData();
                });
              },
            ),
          ),
          // Add toggle for controller source
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _controller = _mapKey.currentState;
                      _controllerSource = "GlobalKey";
                      _updateGeofenceData();
                    });
                  },
                  child: const Text('Use GlobalKey Controller'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => _loadSavedPolygon(),
                  child: const Text('Load Victoria Station Polygon'),
                ),
              ],
            ),
          ),
          // Status Display
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[100],
            width: double.infinity,
            child: Text(
              'Status: $_polygonStatus',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          // JSON Data Display
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey[200],
              width: double.infinity,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Geofence Data (JSON):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _geofenceDataJson,
                        style: const TextStyle(
                          color: Colors.green,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 