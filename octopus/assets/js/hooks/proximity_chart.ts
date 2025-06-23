import { Hook, makeHook } from "phoenix_typed_hook";
import { Chart, registerables } from 'chart.js';

// Register Chart.js components
Chart.register(...registerables);

interface ProximityData {
  sensor: string;
  readings: Array<{ distance: number; timestamp: number }>;
}

class ProximityChartHook extends Hook {
  chart?: Chart | null;
  maxDataPoints: number;

  constructor() {
    super();
  }

  mounted() {
    const ctx = (this.el as HTMLCanvasElement).getContext('2d');
    if (!ctx) {
      console.error('Could not get canvas context');
      return;
    }

    // Create empty chart
    this.chart = new Chart(ctx, {
      type: 'line',
      data: {
        datasets: []
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        scales: {
          x: {
            type: 'linear',
            title: {
              display: false,
              text: 'Timestamp'
            },
            ticks: {
              display: false
            }
          },
          y: {
            title: {
              display: true,
              text: 'Distance (mm)'
            },
            beginAtZero: false
          }
        },
        plugins: {
          legend: {
            display: true,
            position: 'top'
          }
        }
      }
    });

    console.log('Empty proximity chart initialized');

    // Listen for messages from LiveView
    this.handleEvent("proximity-data", (data: ProximityData) => {
      this.addBatch(data.sensor, data.readings);
    });
  }

  addBatch(sensorKey: string, readings: Array<{ distance: number; timestamp: number }>) {
    if (!this.chart) return;

    // Create friendly label
    const sensorLabel = sensorKey.replace(/_/g, ' '); // "sensor_1_0" -> "sensor 1 0"

    // Find existing dataset or create new one
    let dataset = this.chart.data.datasets.find(d => d.label === sensorLabel);

    if (!dataset) {
      // Create new dataset for this sensor
      dataset = {
        label: sensorLabel,
        data: [],
        borderColor: this.getSensorColor(sensorKey),
        backgroundColor: this.getSensorColor(sensorKey, 0.1),
        tension: 0.1,
        pointRadius: 1,
        borderWidth: 1
      };
      this.chart.data.datasets.push(dataset);
    }

    // Add all readings from the batch
    for (const reading of readings) {
      // Add data point using timestamp as X value
      dataset.data.push({
        x: reading.timestamp,
        y: reading.distance
      });
    }

    const maxPoints = 1000;

    // Maintain rolling window - replace the data array if it exceeds max points
    if (dataset.data.length > maxPoints) {
      dataset.data = dataset.data.slice(-maxPoints);
    }

    // Update chart once per batch
    this.chart.update('none');
  }

  getSensorColor(sensorKey: string, alpha: number = 1): string {
    // Generate consistent colors based on sensor key
    const colors = [
      `rgba(255, 99, 132, ${alpha})`,   // Red
      `rgba(54, 162, 235, ${alpha})`,   // Blue  
      `rgba(255, 205, 86, ${alpha})`,   // Yellow
      `rgba(75, 192, 192, ${alpha})`,   // Teal
      `rgba(153, 102, 255, ${alpha})`,  // Purple
      `rgba(255, 159, 64, ${alpha})`,   // Orange
    ];

    // Create a hash from the sensor key string
    let hash = 0;
    for (let i = 0; i < sensorKey.length; i++) {
      const char = sensorKey.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32-bit integer
    }

    const index = Math.abs(hash) % colors.length;
    return colors[index];
  }

  destroyed() {
    if (this.chart) {
      this.chart.destroy();
    }
  }
}

export default makeHook(ProximityChartHook); 