import { Hook, makeHook } from "phoenix_typed_hook";
import { Chart, registerables } from 'chart.js';

// Register Chart.js components
Chart.register(...registerables);

interface AlgorithmData {
  raw: Array<{ distance: number; timestamp: number }>;
  sma: Array<{ distance: number; timestamp: number }>;
  ema: Array<{ distance: number; timestamp: number }>;
  median: Array<{ distance: number; timestamp: number }>;
  combined: Array<{ distance: number; timestamp: number }>;
}

interface ProximityData {
  sensor: string;
  algorithms: AlgorithmData;
}

class ProximityChartHook extends Hook {
  chart?: Chart | null;

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
        },
        elements: {
          point: {
            radius: 0
          },
          line: {
            tension: 0.1
          }
        }
      }
    });

    // Listen for messages from LiveView - use arrow function to preserve 'this'
    this.handleEvent("proximity-data", (data: ProximityData) => {
      this.addAlgorithmBatches(data.sensor, data.algorithms);
    });
  }

  addAlgorithmBatches(sensorKey: string, algorithms: AlgorithmData) {
    if (!this.chart) return;

    // Only process raw and combined algorithms for display
    const algorithmsToShow = ['raw', 'combined'];

    // Process each algorithm, but only show selected ones
    Object.entries(algorithms).forEach(([algorithmName, readings]) => {
      if (algorithmsToShow.includes(algorithmName)) {
        this.addBatch(sensorKey, algorithmName, readings);
      }
    });

    // Update chart once after processing all algorithms
    this.chart.update('none');
  }

  addBatch(sensorKey: string, algorithmName: string, readings: Array<{ distance: number; timestamp: number }>) {
    if (!this.chart) return;

    // Create dataset label combining sensor and algorithm
    const datasetLabel = `${sensorKey} - ${algorithmName.toUpperCase()}`;

    // Find existing dataset or create new one
    let dataset = this.chart.data.datasets.find(d => d.label === datasetLabel);

    if (!dataset) {
      // Create new dataset for this sensor/algorithm combination
      dataset = {
        label: datasetLabel,
        data: [],
        borderColor: this.getAlgorithmColor(algorithmName),
        backgroundColor: this.getAlgorithmColor(algorithmName, 0.1),
        tension: 0.1,
        pointRadius: 0, // No points
        borderWidth: algorithmName === 'combined' ? 2 : 1, // Make combined line slightly thicker, others thinner
        pointBackgroundColor: this.getAlgorithmColor(algorithmName),
        pointBorderColor: this.getAlgorithmColor(algorithmName)
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

    const maxPoints = 100;

    // Maintain rolling window - replace the data array if it exceeds max points
    if (dataset.data.length > maxPoints) {
      dataset.data = dataset.data.slice(-maxPoints);
    }
  }

  getAlgorithmColor(algorithmName: string, alpha: number = 1): string {
    // Predefined colors for each algorithm
    const colors: { [key: string]: string } = {
      raw: `rgba(239, 68, 68, ${alpha})`,      // Red
      sma: `rgba(59, 130, 246, ${alpha})`,     // Blue
      ema: `rgba(249, 115, 22, ${alpha})`, // Orange
      median: `rgba(147, 51, 234, ${alpha})`,  // Purple
      combined: `rgba(34, 197, 94, ${alpha})` // Green
    };

    return colors[algorithmName] || `rgba(128, 128, 128, ${alpha})`; // Default gray
  }

  destroyed() {
    if (this.chart) {
      this.chart.destroy();
    }
  }
}

export default makeHook(ProximityChartHook);