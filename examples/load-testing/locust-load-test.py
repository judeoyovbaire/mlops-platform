"""
Locust load test for KServe inference endpoints
Install: pip install locust
Run: locust -f locust-load-test.py --host=http://sklearn-iris.mlops.svc.cluster.local
Web UI: http://localhost:8089
"""

from locust import HttpUser, task, between
import random
import json


class InferenceUser(HttpUser):
    """Simulates a user making inference requests"""
    
    wait_time = between(1, 3)  # Wait 1-3 seconds between requests
    
    # Sample input data (Iris flower features)
    sample_inputs = [
        [5.1, 3.5, 1.4, 0.2],  # setosa
        [6.2, 3.4, 5.4, 2.3],  # virginica
        [5.9, 3.0, 4.2, 1.5],  # versicolor
        [5.5, 2.4, 3.8, 1.1],  # versicolor
        [6.5, 3.0, 5.2, 2.0],  # virginica
    ]
    
    @task(3)
    def predict_single(self):
        """Most common: single prediction"""
        input_data = random.choice(self.sample_inputs)
        payload = {
            "instances": [input_data]
        }
        
        with self.client.post(
            "/v1/models/sklearn-iris:predict",
            json=payload,
            catch_response=True,
            name="predict_single"
        ) as response:
            if response.status_code == 200:
                try:
                    result = response.json()
                    if "predictions" in result and len(result["predictions"]) > 0:
                        response.success()
                    else:
                        response.failure("No predictions in response")
                except json.JSONDecodeError:
                    response.failure("Invalid JSON response")
            else:
                response.failure(f"Status code: {response.status_code}")
    
    @task(1)
    def predict_batch(self):
        """Less common: batch prediction"""
        batch_size = random.randint(2, 5)
        batch_inputs = random.sample(self.sample_inputs, min(batch_size, len(self.sample_inputs)))
        payload = {
            "instances": batch_inputs
        }
        
        with self.client.post(
            "/v1/models/sklearn-iris:predict",
            json=payload,
            catch_response=True,
            name="predict_batch"
        ) as response:
            if response.status_code == 200:
                try:
                    result = response.json()
                    if "predictions" in result and len(result["predictions"]) == len(batch_inputs):
                        response.success()
                    else:
                        response.failure("Batch size mismatch")
                except json.JSONDecodeError:
                    response.failure("Invalid JSON response")
            else:
                response.failure(f"Status code: {response.status_code}")
    
    @task(1)
    def health_check(self):
        """Health check endpoint"""
        self.client.get("/health", name="health_check")


# Locust configuration
class WebsiteUser(InferenceUser):
    """Main user class"""
    pass
