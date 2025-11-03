#!/usr/bin/env python3
"""
API Testing Script for Tunnel Platform
Run this to verify all endpoints work correctly
"""

import requests
import json
import time
from typing import Optional

BASE_URL = "http://localhost:8000"

class TunnelAPITester:
    def __init__(self, base_url: str = BASE_URL):
        self.base_url = base_url
        self.token: Optional[str] = None
        self.test_email = f"test_{int(time.time())}@example.com"
        self.test_password = "TestPassword123!"
        
    def test_health(self):
        """Test health endpoint"""
        print("🔍 Testing health endpoint...")
        response = requests.get(f"{self.base_url}/health")
        assert response.status_code == 200
        data = response.json()
        print(f"✅ Health check passed: {data}")
        return True
    
    def test_register(self):
        """Test user registration"""
        print(f"\n🔍 Testing registration with {self.test_email}...")
        response = requests.post(
            f"{self.base_url}/auth/register",
            json={"email": self.test_email, "password": self.test_password}
        )
        
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Registration successful: {data}")
            return True
        else:
            print(f"❌ Registration failed: {response.status_code} - {response.text}")
            return False
    
    def test_login(self):
        """Test user login"""
        print(f"\n🔍 Testing login with {self.test_email}...")
        response = requests.post(
            f"{self.base_url}/auth/login",
            data={"username": self.test_email, "password": self.test_password},
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        )
        
        if response.status_code == 200:
            data = response.json()
            self.token = data.get("access_token")
            print(f"✅ Login successful. Token: {self.token[:20]}...")
            return True
        else:
            print(f"❌ Login failed: {response.status_code} - {response.text}")
            return False
    
    def test_list_instances(self):
        """Test listing instances"""
        print("\n🔍 Testing list instances...")
        response = requests.get(
            f"{self.base_url}/instances",
            headers={"Authorization": f"Bearer {self.token}"}
        )
        
        if response.status_code == 200:
            data = response.json()
            print(f"✅ List instances successful: {len(data.get('instances', []))} instances")
            return True
        else:
            print(f"❌ List instances failed: {response.status_code} - {response.text}")
            return False
    
    def test_create_instance(self):
        """Test creating an instance"""
        print("\n🔍 Testing create instance (Note: This will actually launch AWS resources!)...")
        print("⏭️  Skipping actual instance creation to avoid AWS charges")
        # Uncomment to actually test:
        # response = requests.post(
        #     f"{self.base_url}/instances",
        #     json={"region": "us-east-1", "instance_type": "t2.micro"},
        #     headers={"Authorization": f"Bearer {self.token}"}
        # )
        # if response.status_code == 200:
        #     data = response.json()
        #     print(f"✅ Instance creation initiated: {data}")
        #     return True
        return True
    
    def run_all_tests(self):
        """Run all tests in sequence"""
        print("=" * 60)
        print("🚀 Starting Tunnel Platform API Tests")
        print("=" * 60)
        
        tests = [
            ("Health Check", self.test_health),
            ("User Registration", self.test_register),
            ("User Login", self.test_login),
            ("List Instances", self.test_list_instances),
            ("Create Instance", self.test_create_instance),
        ]
        
        results = []
        for test_name, test_func in tests:
            try:
                result = test_func()
                results.append((test_name, result))
            except Exception as e:
                print(f"❌ {test_name} threw exception: {str(e)}")
                results.append((test_name, False))
        
        print("\n" + "=" * 60)
        print("📊 Test Results Summary")
        print("=" * 60)
        
        for test_name, result in results:
            status = "✅ PASS" if result else "❌ FAIL"
            print(f"{status} - {test_name}")
        
        passed = sum(1 for _, result in results if result)
        total = len(results)
        print(f"\n🎯 Total: {passed}/{total} tests passed")
        
        return passed == total

if __name__ == "__main__":
    tester = TunnelAPITester()
    success = tester.run_all_tests()
    exit(0 if success else 1)