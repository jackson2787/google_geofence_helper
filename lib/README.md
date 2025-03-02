# Google Geofence Helper - Controller API

The `InteractiveMapGeofenceController` provides a programmatic way to interact with and query the state of the geofence drawing widget. This approach is useful for integrating the geofence component into larger application flows.

## Getting a Controller Reference

There are two ways to get a reference to the controller:

### 1. Using a GlobalKey

```dart
final _mapKey = GlobalKey<InteractiveMapGeofenceState>();

@override
void initState() {
  super.initState();
  // Get controller reference when widget initializes
  WidgetsBinding.instance.addPostFrameCallback((_) {
    InteractiveMapGeofenceController controller = _mapKey.currentState!;
    // Use controller here
  });
}

@override
Widget build(BuildContext context) {
  return InteractiveMapGeofence(
    key: _mapKey,
    // other properties...
  );
}
```

### 2. Using the onControllerCreated callback

```dart
InteractiveMapGeofenceController? _controller;

@override
Widget build(BuildContext context) {
  return InteractiveMapGeofence(
    onControllerCreated: (controller) {
      _controller = controller;
    },
    // other properties...
  );
}
```

## Controller Methods

### State Manipulation

```dart
// Toggle between satellite and normal map views
void toggleMapType();

// Toggle between edit and view modes
void toggleEditMode();

// Remove the last added vertex
void deleteLastVertex();

// Clear the entire polygon
void clearPolygon();

// Move the camera to a specific position and optional zoom level
Future<void> moveCamera(LatLng position, {double? zoom});
```

### State Query Methods

```dart
// Check if at least one point has been added
bool get isPolygonStarted;

// Check if at least 3 points have been added (minimum for a polygon)
bool get isPolygonComplete;

// Check if currently in edit mode
bool get isInEditMode;

// Check if the polygon has been finalized (closed by clicking near first point)
bool get isPolygonFinalized;

// Get the current points of the polygon (as an unmodifiable list)
List<LatLng> get points;
```

### Get Complete Geofence Data

The controller provides a comprehensive method to get the full geofence data, including status information:

```dart
Map<String, dynamic> getGeofenceData();
```

This method returns a JSON-serializable Map with the following structure:

```json
{
  "status": "finalized",  // String: "no_polygon", "incomplete", "editing", or "finalized"
  "message": "Polygon has been finalized.", // Human-readable status message
  "isComplete": true,     // Boolean: true if 3+ points exist
  "isFinalized": true,    // Boolean: true if polygon has been finalized
  "inEditMode": false,    // Boolean: true if in edit mode
  "pointCount": 5,        // Number of points in the polygon
  "polygon": [            // Array of points with lat/lng in standard format
    {"latitude": 51.5074, "longitude": -0.1278},
    {"latitude": 51.5072, "longitude": -0.1258},
    {"latitude": 51.5069, "longitude": -0.1268},
    {"latitude": 51.5071, "longitude": -0.1288},
    {"latitude": 51.5074, "longitude": -0.1278}
  ]
}
```

### Load Geofence Data

The controller also provides a method to load a previously saved geofence state:

```dart
bool loadGeofenceData(Map<String, dynamic> geofenceData);
```

This method accepts the same format that `getGeofenceData()` returns, allowing you to seamlessly restore a previously saved state:

```dart
// Save the current state when your app closes
final geofenceData = controller.getGeofenceData();
await prefs.setString('saved_geofence', jsonEncode(geofenceData));

// Later, restore the state when your app reopens
final savedJson = prefs.getString('saved_geofence');
if (savedJson != null) {
  final savedGeofence = jsonDecode(savedJson);
  controller.loadGeofenceData(savedGeofence);
}
```

When loading data, the method will:
1. Restore all polygon points
2. Set the finalized state
3. Set the edit mode to match the saved state
4. Update all visual elements accordingly

The method returns `true` if the data was successfully loaded, or `false` if there was an error.

## Example Usage

A full example of using the controller API is available in the example app. This demonstrates:

1. Getting a controller reference using a GlobalKey
2. Updating UI based on geofence state changes
3. Displaying the complete geofence data as JSON
4. Using controller methods to manipulate the geofence
5. Loading a previously saved polygon state (see Victoria train station example)

For a complete implementation, see `example/lib/screens/controller_example.dart`. 