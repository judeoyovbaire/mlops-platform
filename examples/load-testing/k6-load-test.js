// k6 load test for KServe inference endpoints
// Install: brew install k6 (macOS) or follow https://k6.io/docs/getting-started/installation/
// Run: k6 run k6-load-test.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const inferenceLatency = new Trend('inference_latency');

// Test configuration
export const options = {
  stages: [
    { duration: '2m', target: 50 },   // Ramp up to 50 users over 2 minutes
    { duration: '5m', target: 50 },   // Stay at 50 users for 5 minutes
    { duration: '2m', target: 100 },  // Ramp up to 100 users over 2 minutes
    { duration: '5m', target: 100 },  // Stay at 100 users for 5 minutes
    { duration: '2m', target: 0 },    // Ramp down to 0 users over 2 minutes
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'], // 95% of requests < 500ms, 99% < 1s
    http_req_failed: ['rate<0.05'],                 // Error rate < 5%
    errors: ['rate<0.01'],                          // Custom error rate < 1%
    inference_latency: ['p(95)<400'],               // 95% inference latency < 400ms
  },
};

// Inference endpoint (update for your deployment)
const INFERENCE_ENDPOINT = __ENV.INFERENCE_ENDPOINT || 'http://sklearn-iris.mlops.svc.cluster.local/v1/models/sklearn-iris:predict';

// Sample input data (Iris flower features: sepal_length, sepal_width, petal_length, petal_width)
const sampleInputs = [
  [5.1, 3.5, 1.4, 0.2], // setosa
  [6.2, 3.4, 5.4, 2.3], // virginica
  [5.9, 3.0, 4.2, 1.5], // versicolor
  [5.5, 2.4, 3.8, 1.1], // versicolor
  [6.5, 3.0, 5.2, 2.0], // virginica
];

export default function () {
  // Randomly select an input
  const input = sampleInputs[Math.floor(Math.random() * sampleInputs.length)];
  
  const payload = JSON.stringify({
    instances: [input],
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: {
      model: 'sklearn-iris',
      endpoint: 'predict',
    },
  };

  const startTime = Date.now();
  const response = http.post(INFERENCE_ENDPOINT, payload, params);
  const inferenceTime = Date.now() - startTime;

  // Record custom metrics
  inferenceLatency.add(inferenceTime);

  // Validate response
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response has predictions': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.predictions && Array.isArray(body.predictions) && body.predictions.length > 0;
      } catch (e) {
        return false;
      }
    },
    'latency < 500ms': (r) => r.timings.duration < 500,
    'inference latency < 400ms': () => inferenceTime < 400,
  });

  if (!success) {
    errorRate.add(1);
  } else {
    errorRate.add(0);
  }

  sleep(1); // Wait 1 second between requests
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'load-test-results.json': JSON.stringify(data),
  };
}

function textSummary(data, options) {
  const indent = options.indent || '';
  const enableColors = options.enableColors || false;
  
  let summary = '\n';
  summary += `${indent}Load Test Summary\n`;
  summary += `${indent}==================\n\n`;
  summary += `${indent}Total Requests: ${data.metrics.http_reqs.values.count}\n`;
  summary += `${indent}Failed Requests: ${data.metrics.http_req_failed.values.rate * 100}%\n`;
  summary += `${indent}P95 Latency: ${data.metrics.http_req_duration.values['p(95)']}ms\n`;
  summary += `${indent}P99 Latency: ${data.metrics.http_req_duration.values['p(99)']}ms\n`;
  summary += `${indent}Average Inference Latency: ${data.metrics.inference_latency.values.avg}ms\n`;
  
  return summary;
}
