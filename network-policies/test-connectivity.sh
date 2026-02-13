#!/bin/bash

# Network Policy Connectivity Test Script
# This script tests the connectivity before and after applying network policies

set -e

echo "=========================================="
echo "Network Policy Connectivity Test"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to test connectivity
test_connection() {
    local from_pod=$1
    local to_service=$2
    local port=$3
    local should_work=$4
    local description=$5
    
    echo -n "Testing: $description ... "
    
    if kubectl exec -it deployment/$from_pod -- nc -zv -w 2 $to_service $port &> /dev/null; then
        if [ "$should_work" = "yes" ]; then
            echo -e "${GREEN}✓ PASS${NC} (Connection successful)"
        else
            echo -e "${RED}✗ FAIL${NC} (Connection should be blocked!)"
        fi
    else
        if [ "$should_work" = "no" ]; then
            echo -e "${GREEN}✓ PASS${NC} (Connection blocked as expected)"
        else
            echo -e "${RED}✗ FAIL${NC} (Connection should work!)"
        fi
    fi
}

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l tier --timeout=60s

echo ""
echo "=========================================="
echo "Phase 1: Testing WITHOUT Network Policies"
echo "=========================================="
echo ""

test_connection "frontend" "backend" "8080" "yes" "Frontend → Backend (legitimate)"
test_connection "backend" "database" "5432" "yes" "Backend → Database (legitimate)"
test_connection "frontend" "database" "5432" "yes" "Frontend → Database (ATTACK PATH!)"

echo ""
echo "Now apply network policies:"
echo "  kubectl apply -f done/"
echo ""
read -p "Press enter after applying network policies..."

echo ""
echo "=========================================="
echo "Phase 2: Testing WITH Network Policies"
echo "=========================================="
echo ""

test_connection "frontend" "backend" "8080" "yes" "Frontend → Backend (legitimate)"
test_connection "backend" "database" "5432" "yes" "Backend → Database (legitimate)"
test_connection "frontend" "database" "5432" "no" "Frontend → Database (should be blocked)"

echo ""
echo "=========================================="
echo "Test Complete"
echo "=========================================="
