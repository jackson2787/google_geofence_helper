import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

enum MapEditMode {
  view,
  edit,
}

abstract class InteractiveMapGeofenceController {
  void toggleMapType();
  void toggleEditMode();
  void deleteLastVertex();
  void clearPolygon();
  
  // New state query methods
  bool get isPolygonStarted;
  bool get isPolygonComplete;
  bool get isInEditMode;
  bool get isPolygonFinalized;
  
  // Get current points
  List<LatLng> get points;
  
  // Return the full geofence data with status
  Map<String, dynamic> getGeofenceData();
  
  // Load geofence data from a previously saved state
  bool loadGeofenceData(Map<String, dynamic> geofenceData);
  
  // Move camera to a specific position
  Future<void> moveCamera(LatLng position, {double? zoom});
}

class GeofencePolygon {
  final String id;
  final List<LatLng> points;

  GeofencePolygon({
    required this.id,
    required this.points,
  });
}

class InteractiveMapGeofence extends StatefulWidget {
  final LatLng initialPosition;
  final double initialZoom;
  final Function(List<LatLng>)? onPolygonUpdated;
  final Color markerColor;
  final double polygonOpacity;
  final int strokeWidth;
  final bool enableTilt;
  final bool enableRotate;
  final bool enableCompass;
  final double minZoom;
  final double maxZoom;
  final List<LatLng>? initialPoints;
  final bool showControls;
  final Function(InteractiveMapGeofenceController)? onControllerCreated;

  const InteractiveMapGeofence({
    Key? key,
    this.initialPosition = const LatLng(51.5074, -0.1278),
    this.initialZoom = 8.0,
    this.onPolygonUpdated,
    this.markerColor = Colors.blue,
    this.polygonOpacity = 0.3,
    this.strokeWidth = 2,
    this.enableTilt = true,
    this.enableRotate = true,
    this.enableCompass = true,
    this.minZoom = 3.0,
    this.maxZoom = 20.0,
    this.initialPoints,
    this.showControls = true,
    this.onControllerCreated,
  }) : super(key: key);

  static InteractiveMapGeofenceController? of(BuildContext context) {
    return context.findRootAncestorStateOfType<InteractiveMapGeofenceState>();
  }

  @override
  State<InteractiveMapGeofence> createState() => InteractiveMapGeofenceState();
}

class InteractiveMapGeofenceState extends State<InteractiveMapGeofence> implements InteractiveMapGeofenceController {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  List<LatLng> _points = [];
  Set<Marker> _markers = {};
  MapType _currentMapType = MapType.normal;
  MapEditMode _editMode = MapEditMode.view;
  BitmapDescriptor? _customMarker;
  BitmapDescriptor? _firstPointMarker; // Special marker for the first point
  bool _isDragging = false;
  bool _polygonFinalized = false;
  double _markerOffset = 0.00001; // Small offset for better visual alignment
  double _currentZoomLevel = 8.0; // Default zoom level to match initialZoom
  LatLng? _lastMapPosition;

  // Calculate dynamic marker offset based on zoom level
  double get _dynamicMarkerOffset {
    // At high zoom (close-up), use minimal offset for precision
    // At low zoom (far away), use standard offset for visibility
    final double zoomFactor = (_currentZoomLevel - widget.minZoom) / (widget.maxZoom - widget.minZoom);
    // Scale down offset as zoom increases (more precision at higher zoom)
    return _markerOffset * (1.0 - (zoomFactor * 0.7));
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize with initial points if provided
    if (widget.initialPoints != null && widget.initialPoints!.isNotEmpty) {
      _points = List.from(widget.initialPoints!);
    }
    
    // Trigger the onControllerCreated callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.onControllerCreated != null) {
        widget.onControllerCreated!(this);
      }
    });
    
    // Create custom marker icons
    _createCustomMarker().then((marker) {
      setState(() {
        _customMarker = marker;
        if (_points.isNotEmpty) {
          _updateMarkers();
        }
      });
    });
    
    _createFirstPointMarker().then((marker) {
      setState(() {
        _firstPointMarker = marker;
        if (_points.isNotEmpty) {
          _updatePolygon();
        }
      });
    });
    _currentZoomLevel = widget.initialZoom;
  }

  void _updateMarkers() {
    if (_customMarker == null) return;
    
    setState(() {
      _markers.clear();
      
      // Only show markers in edit mode
      if (_editMode == MapEditMode.edit) {
        for (int i = 0; i < _points.length; i++) {
          final point = _points[i];
          final bool isFirstPoint = i == 0;
          
          // Apply a dynamic offset based on zoom level
          final double currentOffset = _dynamicMarkerOffset;
          final LatLng markerPosition = LatLng(
            point.latitude - currentOffset, // Dynamically adjusted offset
            point.longitude
          );
          
          // Use a different marker for the first point if we have enough points for a polygon
          // and we're not finalized yet
          final BitmapDescriptor markerIcon = (_points.length >= 3 && isFirstPoint && !_polygonFinalized) 
              ? _firstPointMarker ?? _customMarker!
              : _customMarker!;
          
          _markers.add(
            Marker(
              markerId: MarkerId('vertex_$i'),
              position: markerPosition,
              draggable: true,
              icon: markerIcon,
              anchor: const Offset(0.5, 0.5),
              onTap: isFirstPoint && _points.length >= 3 && !_polygonFinalized 
                  ? () { 
                      print('First marker tapped - finalizing polygon');
                      _finalizePolygon(); 
                    } 
                  : null,
              onDragStart: (_) {
                setState(() {
                  _isDragging = true;
                });
              },
              onDrag: (newPosition) {
                // Update position in real-time while dragging
                _handleMarkerDrag(i, newPosition);
              },
              onDragEnd: (newPosition) {
                _handleMarkerDragEnd(i, newPosition);
              },
            ),
          );
        }
      }
    });
  }

  void _handleMarkerDrag(int index, LatLng newPosition) {
    setState(() {
      // Compensate for the offset we applied to the marker (using dynamic offset)
      _points[index] = LatLng(
        newPosition.latitude + _dynamicMarkerOffset,
        newPosition.longitude
      );
      _updatePolygon();
    });
  }

  void _handleMarkerDragEnd(int index, LatLng newPosition) {
    setState(() {
      _isDragging = false;
      
      // Compensate for the offset we applied to the marker (using dynamic offset)
      _points[index] = LatLng(
        newPosition.latitude + _dynamicMarkerOffset,
        newPosition.longitude
      );
      
      _updateMarkers();
      _updatePolygon();
    });
    _notifyPolygonUpdate();
  }

  Future<void> _handleMapTap(LatLng position) async {
    // Store the position regardless of edit mode for hover effects
    _lastMapPosition = position;
    
    if (_editMode != MapEditMode.edit) return;

    // Check if we're clicking in the UI control area
    final GoogleMapController controller = await _controller.future;
    final ScreenCoordinate screenCoordinate = await controller.getScreenCoordinate(position);
    
    // Define the button area (top-right corner)
    final double buttonAreaWidth = 80;
    final double buttonAreaHeight = 350;

    // Check if tap is in the button area
    if (screenCoordinate.x >= MediaQuery.of(context).size.width - buttonAreaWidth &&
        screenCoordinate.y <= buttonAreaHeight) {
      return;
    }

    // Check if clicking near another point (to prevent accidentally placing points too close)
    if (_isNearAnyExistingPoint(position) && _points.length > 0) {
      print('Tap too close to existing point - ignoring');
      return;
    }

    // Check if clicking near the first point to close the polygon
    if (_points.length >= 3 && _isNearFirstPoint(position)) {
      print('Finalizing polygon on tap');
      _finalizePolygon();
      return;
    }

    setState(() {
      _points.add(position);
      _updateMarkers();
      _updatePolygon();
    });

    _notifyPolygonUpdate();
  }

  bool _isNearFirstPoint(LatLng position) {
    if (_points.isEmpty) return false;
    
    // Dynamic threshold based on zoom level
    // At zoom level 20 (max zoom), threshold is smallest (most precise)
    // At zoom level 1 (min zoom), threshold is largest (more forgiving)
    final double zoomFactor = 1.0 - ((_currentZoomLevel - widget.minZoom) / (widget.maxZoom - widget.minZoom));
    final double baseThreshold = 0.00002; // Increased base threshold for easier snapping
    final double maxMultiplier = 30.0; // Increased maximum multiplier at minimum zoom
    final double threshold = baseThreshold * (1 + (zoomFactor * maxMultiplier));
    
    final LatLng firstPoint = _points.first;
    final double distance = 
        (position.latitude - firstPoint.latitude).abs() +
        (position.longitude - firstPoint.longitude).abs();
    
    // Debug point for development
    print('Distance to first point: $distance, threshold: $threshold, zoom: $_currentZoomLevel');
    
    return distance < threshold;
  }

  // Track precision mode toggle
  bool _precisionModeEnabled = false;

  // Toggle precision mode (allows placing points very close together)
  void _togglePrecisionMode() {
    setState(() {
      _precisionModeEnabled = !_precisionModeEnabled;
    });
  }

  // Check if a tap position is too close to any existing marker
  bool _isNearAnyExistingPoint(LatLng position) {
    // Skip check if we have no points yet
    if (_points.isEmpty) return false;
    
    // If precision mode is enabled and we're at high zoom, allow placing points close together
    if (_precisionModeEnabled && _currentZoomLevel >= 17) {
      return false;
    }
    
    // Use a smaller threshold for high zoom levels
    final double zoomFactor = (_currentZoomLevel - widget.minZoom) / (widget.maxZoom - widget.minZoom);
    final double baseDistanceThreshold = 0.000005; // Base threshold at minimum zoom
    
    // Gradually decrease threshold as zoom increases, but with a lower bound
    // At max zoom, allow points to be placed up to 10x closer
    final double minThresholdMultiplier = 0.1; // At max zoom, threshold is 10% of base
    final double thresholdMultiplier = 1.0 - (zoomFactor * (1.0 - minThresholdMultiplier));
    final double threshold = baseDistanceThreshold * thresholdMultiplier;
    
    // Check distance to all existing points
    for (LatLng point in _points) {
      final double distance = 
          (position.latitude - point.latitude).abs() +
          (position.longitude - point.longitude).abs();
      
      if (distance < threshold) {
        return true; // Too close to an existing point
      }
    }
    
    return false;
  }

  void _finalizePolygon() {
    if (_points.length < 3) return;

    setState(() {
      _polygonFinalized = true;
      // We don't need to add the first point again - Google Maps will automatically close the polygon visually
      // This ensures we maintain exactly the coordinates the user placed without duplication
      _updateMarkers();
    });
    
    _notifyPolygonUpdate();
  }

  void _updatePolygon() {
    // Just trigger a rebuild without any polygon-specific logic
    setState(() {});
  }

  Set<Polygon> _createPolygon() {
    // Only create a polygon if we've explicitly finalized it
    if (!_polygonFinalized || _points.length < 3) return {};

    return {
      Polygon(
        polygonId: const PolygonId('building'),
        points: _points,
        strokeWidth: widget.strokeWidth,
        strokeColor: widget.markerColor,
        fillColor: widget.markerColor.withOpacity(widget.polygonOpacity),
        geodesic: true,
      ),
    };
  }

  Set<Polyline> _createPolylines() {
    if (_points.length < 2) return {}; // Need at least 2 points
    
    // If polygon is finalized, don't show polylines (the polygon will be shown instead)
    if (_polygonFinalized) return {};
    
    // Regular polyline connecting all points
    Set<Polyline> polylines = {
      Polyline(
        polylineId: const PolylineId('drawing_line'),
        points: _points,
        color: widget.markerColor,
        width: widget.strokeWidth,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      )
    };
    
    // If we have at least 3 points, add a "closing line" from last point to first point
    // to show that the polygon can be closed
    if (_points.length >= 3) {
      // Check if we're hovering near first point - this is a visual indicator only
      bool nearFirstPoint = false;
      if (_lastMapPosition != null) {
        final double zoomFactor = 1.0 - ((_currentZoomLevel - widget.minZoom) / (widget.maxZoom - widget.minZoom));
        final double baseThreshold = 0.000005; 
        final double maxMultiplier = 20.0;
        final double threshold = baseThreshold * (1 + (zoomFactor * maxMultiplier));
        
        final LatLng firstPoint = _points.first;
        final double distance = 
            (_lastMapPosition!.latitude - firstPoint.latitude).abs() +
            (_lastMapPosition!.longitude - firstPoint.longitude).abs();
        
        nearFirstPoint = distance < threshold;
      }
      
      // Add a dashed or highlighted line to the first point if we're hovering near it
      if (nearFirstPoint) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('closing_hint_line'),
            points: [_points.last, _points.first],
            color: Colors.green, // Use a different color to indicate closing
            width: widget.strokeWidth + 1,
            patterns: [PatternItem.dot, PatternItem.gap(3)], // Dashed line
          )
        );
      }
    }
    
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: widget.initialPosition,
            zoom: widget.initialZoom,
          ),
          mapType: _currentMapType,
          polygons: _createPolygon(),
          polylines: _createPolylines(),
          markers: _markers,
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
            _removePOIs();
          },
          onTap: _handleMapTap,
          onCameraMove: _onCameraMove,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: widget.enableCompass,
          buildingsEnabled: true,
          minMaxZoomPreference: MinMaxZoomPreference(widget.minZoom, widget.maxZoom),
          rotateGesturesEnabled: widget.enableRotate,
          tiltGesturesEnabled: widget.enableTilt,
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
        ),
        if (widget.showControls) _buildControls(),
      ],
    );
  }

  Widget _buildControls() {
    return Positioned(
      top: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            FloatingActionButton(
              heroTag: "mapType",
              onPressed: () {
                Future.microtask(_toggleMapType);
              },
              child: Icon(
                _currentMapType == MapType.normal ? Icons.satellite : Icons.map,
              ),
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              heroTag: "editMode",
              onPressed: () {
                Future.microtask(_toggleEditMode);
              },
              child: Icon(_editMode == MapEditMode.view ? Icons.edit : Icons.check),
            ),
            if (_editMode == MapEditMode.edit) ...[
              if (_currentZoomLevel >= 17) ...[
                // Only show precision mode toggle at high zoom levels
                const SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: "precisionMode",
                  onPressed: () {
                    Future.microtask(_togglePrecisionMode);
                  },
                  backgroundColor: _precisionModeEnabled ? Colors.amber : Colors.blueGrey,
                  child: const Icon(Icons.straighten), // Precision measurement icon
                ),
              ],
              if (_points.isNotEmpty) ...[
                const SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: "undo",
                  onPressed: () {
                    Future.microtask(_deleteLastVertex);
                  },
                  child: const Icon(Icons.undo),
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: "delete",
                  onPressed: () {
                    Future.microtask(_clearPolygon);
                  },
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<BitmapDescriptor> _createCustomMarker() async {
    // Adjust visual size based on device and zoom level
    // Base sizes (logical pixels)
    double visualSize = kIsWeb ? 16.0 : 40.0;
    double touchSize = kIsWeb ? 24.0 : 80.0;

    // Adjust for zoom level if we're already initialized
    if (_currentZoomLevel > 15) {
      // Smaller markers at high zoom for precision
      visualSize *= 0.8;
    } else if (_currentZoomLevel < 10) {
      // Larger markers at low zoom for visibility
      visualSize *= 1.2;
    }

    // Get device pixel ratio
    final double devicePixelRatio = ui.window.devicePixelRatio;

    // Scale sizes for pixel density
    final double scaledVisualSize = visualSize * devicePixelRatio;
    final double scaledTouchSize = touchSize * devicePixelRatio;

    final pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    // Scale the canvas for pixel density
    canvas.scale(devicePixelRatio);

    final Paint fillPaint = Paint()
      ..color = widget.markerColor.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = widget.markerColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Center of the touch target area (in logical pixels)
    final Offset center = Offset(touchSize / 2, touchSize / 2);
    
    // Draw invisible touch target circle
    canvas.drawCircle(
      center,
      touchSize / 2,
      Paint()..color = Colors.transparent,
    );

    // Draw different marker shapes based on platform
    if (kIsWeb) {
      // Draw a triangle with two points at the top for web
      final Path trianglePath = Path();
      
      // Calculate triangle dimensions based on visualSize
      final double halfWidth = visualSize / 2;
      final double height = visualSize;
      
      // Define the triangle points (two at top, one at bottom)
      // Start from left point at top
      trianglePath.moveTo(center.dx - halfWidth, center.dy - halfWidth / 2);
      // Draw line to right point at top
      trianglePath.lineTo(center.dx + halfWidth, center.dy - halfWidth / 2);
      // Draw line to bottom center point
      trianglePath.lineTo(center.dx, center.dy + halfWidth);
      // Close the path to complete the triangle
      trianglePath.close();
      
      // Fill and stroke the triangle
      canvas.drawPath(trianglePath, fillPaint);
      canvas.drawPath(trianglePath, borderPaint);
    } else {
      // Draw a circle for mobile platforms
      canvas.drawCircle(center, visualSize / 2, fillPaint);
      canvas.drawCircle(center, visualSize / 2, borderPaint);
    }

    final picture = pictureRecorder.endRecording();
    final img = await picture.toImage(
      scaledTouchSize.toInt(),
      scaledTouchSize.toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List bytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(bytes);
  }

  Future<BitmapDescriptor> _createFirstPointMarker() async {
    // Base sizes (logical pixels)
    double visualSize = kIsWeb ? 16.0 : 48.0;
    double touchSize = kIsWeb ? 24.0 : 96.0;
    
    // Adjust for zoom level if we're already initialized
    if (_currentZoomLevel > 15) {
      // Smaller markers at high zoom for precision
      visualSize *= 0.8;
    } else if (_currentZoomLevel < 10) {
      // Larger markers at low zoom for visibility
      visualSize *= 1.2;
    }

    // Get device pixel ratio
    final double devicePixelRatio = ui.window.devicePixelRatio;

    // Scale sizes for pixel density
    final double scaledVisualSize = visualSize * devicePixelRatio;
    final double scaledTouchSize = touchSize * devicePixelRatio;

    final pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    // Scale the canvas for pixel density
    canvas.scale(devicePixelRatio);

    final Paint fillPaint = Paint()
      ..color = Colors.green.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Center of the touch target area (in logical pixels)
    final Offset center = Offset(touchSize / 2, touchSize / 2);
    
    // Draw invisible touch target circle
    canvas.drawCircle(
      center,
      touchSize / 2,
      Paint()..color = Colors.transparent,
    );

    // Draw different shapes based on platform, but both should be green
    if (kIsWeb) {
      // Draw a triangle for web, but with green colors
      final Path trianglePath = Path();
      
      // Calculate triangle dimensions
      final double halfWidth = visualSize / 2;
      final double height = visualSize;
      
      // Define the triangle points
      trianglePath.moveTo(center.dx - halfWidth, center.dy - halfWidth / 2);
      trianglePath.lineTo(center.dx + halfWidth, center.dy - halfWidth / 2);
      trianglePath.lineTo(center.dx, center.dy + halfWidth);
      trianglePath.close();
      
      // Fill and stroke the triangle
      canvas.drawPath(trianglePath, fillPaint);
      canvas.drawPath(trianglePath, borderPaint);
    } else {
      // Circle for mobile
      canvas.drawCircle(center, visualSize / 2, fillPaint);
      canvas.drawCircle(center, visualSize / 2, borderPaint);
    }
    
    // Add a "X" symbol to indicate "click to close" for both platforms
    final Paint symbolPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    // Draw a simple "X" symbol
    final double symbolSize = visualSize / 4;
    canvas.drawLine(
      Offset(center.dx - symbolSize, center.dy - symbolSize),
      Offset(center.dx + symbolSize, center.dy + symbolSize),
      symbolPaint
    );
    canvas.drawLine(
      Offset(center.dx + symbolSize, center.dy - symbolSize),
      Offset(center.dx - symbolSize, center.dy + symbolSize),
      symbolPaint
    );

    final picture = pictureRecorder.endRecording();
    final img = await picture.toImage(
      scaledTouchSize.toInt(),
      scaledTouchSize.toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List bytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(bytes);
  }

  Future<void> _removePOIs() async {
    final GoogleMapController controller = await _controller.future;
    await controller.setMapStyle('''
    [
      {
        "featureType": "poi",
        "stylers": [{ "visibility": "off" }]
      },
      {
        "featureType": "poi.business",
        "stylers": [{ "visibility": "off" }]
      },
      {
        "featureType": "poi.park",
        "stylers": [{ "visibility": "off" }]
      },
      {
        "featureType": "road",
        "stylers": [{ "visibility": "on" }]
      }
    ]
    ''');
  }

  void _toggleMapType() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal
          ? MapType.satellite
          : MapType.normal;
    });
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = _editMode == MapEditMode.view ? MapEditMode.edit : MapEditMode.view;
      _isDragging = false;
      _updateMarkers();
    });
  }

  void _deleteLastVertex() {
    if (_points.isEmpty) return;
    
    setState(() {
      _points.removeLast();
      _updateMarkers();
      _polygonFinalized = false;
    });

    _notifyPolygonUpdate();
  }

  void _clearPolygon() {
    setState(() {
      _points.clear();
      _markers.clear();
      _polygonFinalized = false;
    });
    _notifyPolygonUpdate();
  }

  @override
  void toggleMapType() {
    _toggleMapType();
  }

  @override
  void toggleEditMode() {
    _toggleEditMode();
  }

  @override
  void deleteLastVertex() {
    _deleteLastVertex();
  }

  @override
  void clearPolygon() {
    _clearPolygon();
  }

  void _notifyPolygonUpdate() {
    if (widget.onPolygonUpdated != null) {
      widget.onPolygonUpdated!(_points);
    }
  }

  void _onCameraMove(CameraPosition position) {
    _currentZoomLevel = position.zoom;
    // Force a rebuild for polyline hover effects
    if (_editMode == MapEditMode.edit && _points.length >= 3) {
      setState(() {});
    }
  }

  @override
  bool get isPolygonStarted => _points.isNotEmpty;

  @override
  bool get isPolygonComplete => _points.length >= 3;

  @override
  bool get isInEditMode => _editMode == MapEditMode.edit;

  @override
  bool get isPolygonFinalized => _polygonFinalized;

  @override
  List<LatLng> get points => List.unmodifiable(_points);

  @override
  Map<String, dynamic> getGeofenceData() {
    // Determine status
    String status = "no_polygon";
    String message = "No polygon has been created.";
    
    if (_points.isEmpty) {
      status = "no_polygon";
      message = "No polygon has been created.";
    } else if (_points.length < 3) {
      status = "incomplete";
      message = "Polygon is incomplete. Add at least 3 points.";
    } else if (_editMode == MapEditMode.edit) {
      status = "editing";
      message = "Polygon is in edit mode. Tap 'Done' to finalize.";
    } else if (_polygonFinalized) {
      status = "finalized";
      message = "Polygon has been finalized.";
    }
    
    // Create polygon data with coordinates in standardized format
    List<Map<String, double>> polygonPoints = _points.map((point) => {
      'latitude': point.latitude,
      'longitude': point.longitude
    }).toList();
    
    // Return structured data
    return {
      'status': status,
      'message': message,
      'isComplete': _points.length >= 3,
      'isFinalized': _polygonFinalized,
      'inEditMode': _editMode == MapEditMode.edit,
      'pointCount': _points.length,
      'polygon': polygonPoints,
    };
  }

  @override
  bool loadGeofenceData(Map<String, dynamic> geofenceData) {
    try {
      // Clear current state first
      _clearPolygon();
      
      // Check if we have polygon data
      if (geofenceData.containsKey('polygon') && geofenceData['polygon'] is List) {
        final polygonData = geofenceData['polygon'] as List;
        
        // Convert polygon data to LatLng points
        final List<LatLng> restoredPoints = [];
        for (final point in polygonData) {
          if (point is Map && point.containsKey('latitude') && point.containsKey('longitude')) {
            restoredPoints.add(LatLng(
              point['latitude'] as double,
              point['longitude'] as double
            ));
          }
        }
        
        if (restoredPoints.isNotEmpty) {
          setState(() {
            _points = restoredPoints;
            
            // Restore finalized state if it exists (default to false if not specified)
            _polygonFinalized = geofenceData['isFinalized'] ?? false;
            
            // Update the edit mode to match the saved state if specified
            final bool shouldBeInEditMode = geofenceData['inEditMode'] ?? false;
            if (shouldBeInEditMode != (_editMode == MapEditMode.edit)) {
              _toggleEditMode();
            }
            
            // Update markers and visual representation
            _updateMarkers();
            _updatePolygon();
          });
          
          // Notify listeners of the change
          _notifyPolygonUpdate();
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error loading geofence data: $e');
      return false;
    }
  }

  @override
  Future<void> moveCamera(LatLng position, {double? zoom}) async {
    final GoogleMapController controller = await _controller.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: zoom ?? _currentZoomLevel,
        ),
      ),
    );
  }
} 