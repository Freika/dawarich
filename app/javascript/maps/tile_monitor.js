export class TileMonitor {
  constructor(monitoringEnabled, apiKey) {
    this.monitoringEnabled = monitoringEnabled;
    this.apiKey = apiKey;
    this.tileQueue = 0;
    this.tileUpdateInterval = null;
  }

  startMonitoring() {
    // Only start the interval if monitoring is enabled
    if (!this.monitoringEnabled) return;

    // Clear any existing interval
    if (this.tileUpdateInterval) {
      clearInterval(this.tileUpdateInterval);
    }

    // Set up a regular interval to send stats
    this.tileUpdateInterval = setInterval(() => {
      this.sendTileUsage();
    }, 5000); // Exactly every 5 seconds
  }

  stopMonitoring() {
    if (this.tileUpdateInterval) {
      clearInterval(this.tileUpdateInterval);
      this.sendTileUsage(); // Send any remaining stats
    }
  }

  recordTileLoad() {
    if (!this.monitoringEnabled) return;
    this.tileQueue += 1;
  }

  sendTileUsage() {
    // Don't send if monitoring is disabled or queue is empty
    if (!this.monitoringEnabled || this.tileQueue === 0) return;

    const currentCount = this.tileQueue;
    console.log('Sending tile usage batch:', currentCount);

    fetch('/api/v1/maps/tile_usage', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`
      },
      body: JSON.stringify({
        tile_usage: {
          count: currentCount
        }
      })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      // Only subtract sent count if it hasn't changed
      if (this.tileQueue === currentCount) {
        this.tileQueue = 0;
      } else {
        this.tileQueue -= currentCount;
      }
      console.log('Tile usage batch sent successfully');
    })
    .catch(error => console.error('Error recording tile usage:', error));
  }
}
