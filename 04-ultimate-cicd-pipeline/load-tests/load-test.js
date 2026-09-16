import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const apiLatency = new Trend('api_latency');

const BASE_URL = __ENV.TARGET_URL || 'https://staging.example.com';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 50 },
    { duration: '2m', target: 50 },
    { duration: '30s', target: 100 },
    { duration: '1m', target: 100 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    errors: ['rate<0.01'],
    api_latency: ['p(95)<500'],
  },
};

export default function () {
  const res = http.get(`${BASE_URL}/api/endpoint`, {
    headers: {
      'Content-Type': 'application/json',
    },
    timeout: '10s',
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'response body not empty': (r) => r.body.length > 0,
  });

  errorRate.add(res.status !== 200);
  apiLatency.add(res.timings.duration);

  sleep(1);
}

export function handleSummary(data) {
  const failThreshold = data.root_group.thresholds.errors;
  const durationThreshold = data.root_group.thresholds.http_req_duration;

  return {
    stdout: JSON.stringify(data, null, 2),
  };
}
