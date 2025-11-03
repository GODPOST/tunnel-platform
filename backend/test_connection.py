# test_connection.py - Test backend connectivity
import requests
import json

BASE_URL = "http://localhost:8000"

def test_health():
    """Test health endpoint"""
    print("🔍 Testing health endpoint...")
    try:
        response = requests.get(f"{BASE_URL}/health")
        print(f"✅ Health check: {response.status_code}")
        print(f"   Response: {response.json()}")
        return True
    except Exception as e:
        print(f"❌ Health check failed: {e}")
        return False

def test_register():
    """Test user registration"""
    print("\n🔍 Testing registration...")
    try:
        data = {
            "email": "test@example.com",
            "password": "testpassword123"
        }
        response = requests.post(
            f"{BASE_URL}/auth/register",
            json=data,
            headers={"Content-Type": "application/json"}
        )
        print(f"{'✅' if response.status_code in [200, 201] else '❌'} Registration: {response.status_code}")
        print(f"   Response: {response.json()}")
        return response.status_code in [200, 201, 400]  # 400 if already exists
    except Exception as e:
        print(f"❌ Registration failed: {e}")
        return False

def test_login():
    """Test user login"""
    print("\n🔍 Testing login...")
    try:
        data = {
            "username": "test@example.com",
            "password": "testpassword123"
        }
        response = requests.post(
            f"{BASE_URL}/auth/login",
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        )
        print(f"{'✅' if response.status_code == 200 else '❌'} Login: {response.status_code}")
        result = response.json()
        print(f"   Response: {result}")
        
        if response.status_code == 200 and 'access_token' in result:
            return result['access_token']
        return None
    except Exception as e:
        print(f"❌ Login failed: {e}")
        return None

def test_instances(token):
    """Test instances endpoint"""
    print("\n🔍 Testing instances endpoint...")
    try:
        response = requests.get(
            f"{BASE_URL}/instances",
            headers={"Authorization": f"Bearer {token}"}
        )
        print(f"{'✅' if response.status_code == 200 else '❌'} Instances: {response.status_code}")
        print(f"   Response: {response.json()}")
        return response.status_code == 200
    except Exception as e:
        print(f"❌ Instances test failed: {e}")
        return False

def run_all_tests():
    """Run all connectivity tests"""
    print("🚀 Starting backend connectivity tests...\n")
    print("=" * 50)
    
    # Test 1: Health check
    if not test_health():
        print("\n❌ Backend is not running!")
        return False
    
    # Test 2: Register
    test_register()
    
    # Test 3: Login
    token = test_login()
    if not token:
        print("\n❌ Could not get access token")
        return False
    
    # Test 4: Protected endpoint
    test_instances(token)
    
    print("\n" + "=" * 50)
    print("✅ All tests completed!")
    return True

if __name__ == "__main__":
    run_all_tests()