import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { geoLocationManager } from '@kit.LocationKit';
import { notificationManager } from '@kit.NotificationKit';
import { promptAction } from '@kit.ArkUI';
import vibrator from '@ohos.vibrator'

@Entry
@Component
struct Index {

  private mapOptions: mapCommon.MapOptions | null = null;
  private callback?: AsyncCallback<map.MapComponentController>;
  private mapController?: map.MapComponentController;
  private mapEventManager?: map.MapEventManager;
  @State currentLocation: geoLocationManager.Location | null = null;
  @State vibrationInterval: number | undefined = undefined;
  private locationRequest: geoLocationManager.LocationRequest = {
    priority: geoLocationManager.LocationRequestPriority.ACCURACY,
    timeInterval: 0,
    distanceInterval: 0,
    maxAccuracy: 0
  };
  private locationChangeCallback?: (location: geoLocationManager.Location) => void;
  private mapCircle?: map.MapCircle;
  private isInsideGeoFence: boolean = true;
  private geoFenceCenter: mapCommon.LatLng | null = null;
  private geoFenceRadius: number = 100;

  aboutToAppear(): void {
    const params = router.getParams() as mapCommon.MapOptions
    if(params) {
      this.mapOptions = params
    }

    this.locationChangeCallback = (location: geoLocationManager.Location) => {
      this.currentLocation = location;
      this.centerMapOnLocation(location);
      this.checkGeoFenceStatus(location);
    };

    this.callback = async (err, mapController) => {
      if (!err) {
        this.mapController = mapController;
        this.mapEventManager = this.mapController.getEventManager();
        this.mapController.setMyLocationEnabled(true);
        this.mapController.setMyLocationControlsEnabled(true);

        let mapCircleOptions: mapCommon.MapCircleOptions = {
          center: {
            latitude: this.mapOptions!.position.target.latitude,
            longitude: this.mapOptions!.position.target.longitude
          },
          radius: 100,
          clickable: true,
          fillColor: 0xFFFFC100,
          strokeColor: 0xFFFF0000,
          strokeWidth: 10,
          visible: true,
          zIndex: 5
        }

        this.mapCircle = await this.mapController.addCircle(mapCircleOptions);
        this.geoFenceCenter = mapCircleOptions.center;
        this.geoFenceRadius = mapCircleOptions.radius;
        this.startLocationUpdates();

        let callback = () => {
          if (this.currentLocation) {
            this.centerMapOnLocation(this.currentLocation);
          }
        }
        this.mapEventManager.on("mapLoad", callback);
      } else {
        console.error(`Failed to initialize the map. Code: ${err.code}; message: ${err.message}`);
      }
    };
  }

  private centerMapOnLocation(location: geoLocationManager.Location) {
    if (this.mapController) {
      const cameraPosition: mapCommon.CameraPosition = {
        target: {
          latitude: location.latitude,
          longitude: location.longitude,
        },
        zoom: 15,
        tilt: 0,
        bearing: 0
      };

      let cameraUpdate = map.newCameraPosition(cameraPosition);
      this.mapController.animateCamera(cameraUpdate, 1000);
    }
  }

  private startVibration(): void {
    this.stopVibration();
    vibrator.startVibration({
      type: 'time',
      duration: 10000
    }, {
      id: 0,
      usage: 'alarm'
    });
  }

  private stopVibration() {
    if (this.vibrationInterval !== undefined) {
      clearInterval(this.vibrationInterval);
      this.vibrationInterval = undefined;
      vibrator.stopVibration().catch((err: BusinessError) => {
        console.error('Failed to stop vibration:', err);
      });
    }
  }

  private checkGeoFenceStatus(location: geoLocationManager.Location): void {
    if (!this.geoFenceCenter) return;

    const distance = this.calculateDistance(
      location.latitude,
      location.longitude,
      this.geoFenceCenter.latitude,
      this.geoFenceCenter.longitude
    );

    const nowInside = distance <= this.geoFenceRadius;

    if (nowInside !== this.isInsideGeoFence) {
      this.isInsideGeoFence = nowInside;

      if (nowInside) {
        this.showNotification("You are in safe zone!", "You have entered the safe zone again");
        this.stopVibration();
      } else {
        this.showNotification("WARNING!", "DANGER ZONE!");
        this.startVibration();
        this.showAlert("WARNING!", "DANGER ZONE");
      }
    }
  }

  private calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371000;
    const dLat = this.deg2rad(lat2 - lat1);
    const dLon = this.deg2rad(lon2 - lon1);

    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(this.deg2rad(lat1)) * Math.cos(this.deg2rad(lat2)) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);

    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distance = R * c;

    return distance;
  }

  private deg2rad(deg: number): number {
    return deg * (Math.PI / 180);
  }

  private async showNotification(title: string, content: string): Promise<void> {
    try {
      await notificationManager.publish({
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: content
          }
        },
        id: 1
      });
    } catch (error) {
      console.error('Notification error:', error);
    }
  }

  private async showAlert(title: string, message: string): Promise<void> {
    try {
      await promptAction.showDialog({
        title: title,
        message: message,
        buttons: [
          {
            text: 'OK',
            color: '#007AFF'
          }
        ]
      });
      this.stopVibration();
    } catch (error) {
      console.error('Alert error:', error);
    }
  }

  private startLocationUpdates() {
    try {
      geoLocationManager.on('locationChange', this.locationRequest, this.locationChangeCallback!);
    } catch (error) {
      console.error('Location updates error:', error);
    }
  }

  aboutToDisappear(): void {
    if (this.locationChangeCallback) {
      geoLocationManager.off('locationChange', this.locationChangeCallback);
    }
  }

  build() {
    Stack() {
      MapComponent({ mapOptions: this.mapOptions!, mapCallback: this.callback }).width('100%').height('100%');
    }.height('100%')
  }
}