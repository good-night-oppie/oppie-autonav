// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

package sandbox

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestSandboxManagerCreation tests manager initialization
func TestSandboxManagerCreation(t *testing.T) {
	template := SandboxConfig{
		MemoryMB: 512,
		CPUCount: 1,
		VMID:     "template-vm",
	}
	
	manager := NewSandboxManager(5, template)
	require.NotNil(t, manager)
	assert.NotNil(t, manager.GetPool())
}

// TestSandboxManagerBasicOperations tests basic manager operations
func TestSandboxManagerBasicOperations(t *testing.T) {
	ctx := context.Background()
	template := SandboxConfig{
		MemoryMB: 512,
		CPUCount: 1,
	}
	
	// Use mock pool for testing
	mockPool := NewMockSandboxPool(5)
	manager := &DefaultSandboxManager{
		pool:      mockPool,
		sandboxes: make(map[string]Sandbox),
	}
	
	// Test creating sandbox
	config := SandboxConfig{VMID: "test-sandbox"}
	sandbox, err := manager.CreateSandbox(ctx, config)
	require.NoError(t, err)
	assert.Equal(t, "test-sandbox", sandbox.ID())
	
	// Test getting sandbox
	retrieved, err := manager.GetSandbox(ctx, sandbox.ID())
	require.NoError(t, err)
	assert.Equal(t, sandbox.ID(), retrieved.ID())
	
	// Test listing sandboxes
	infos, err := manager.ListSandboxes(ctx)
	require.NoError(t, err)
	assert.Len(t, infos, 1)
	assert.Equal(t, "test-sandbox", infos[0].ID)
	
	// Test releasing sandbox
	err = manager.ReleaseSandbox(ctx, sandbox)
	require.NoError(t, err)
	
	// Test that sandbox is no longer tracked
	_, err = manager.GetSandbox(ctx, sandbox.ID())
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
}

// TestSandboxManagerMultipleSandboxes tests managing multiple sandboxes
func TestSandboxManagerMultipleSandboxes(t *testing.T) {
	ctx := context.Background()
	mockPool := NewMockSandboxPool(10)
	manager := &DefaultSandboxManager{
		pool:      mockPool,
		sandboxes: make(map[string]Sandbox),
	}
	
	// Create multiple sandboxes
	sandboxCount := 5
	sandboxes := make([]Sandbox, sandboxCount)
	
	for i := 0; i < sandboxCount; i++ {
		config := SandboxConfig{VMID: "multi-test-" + string(rune(i))}
		sandbox, err := manager.CreateSandbox(ctx, config)
		require.NoError(t, err)
		sandboxes[i] = sandbox
	}
	
	// Verify all sandboxes are tracked
	infos, err := manager.ListSandboxes(ctx)
	require.NoError(t, err)
	assert.Len(t, infos, sandboxCount)
	
	// Test getting sandbox stats
	stats, err := manager.GetSandboxStats(ctx)
	require.NoError(t, err)
	assert.Equal(t, sandboxCount, stats.TotalSandboxes)
	
	// Test destroying specific sandbox
	err = manager.DestroySandbox(ctx, sandboxes[0].ID())
	require.NoError(t, err)
	
	// Verify sandbox count decreased
	infos, err = manager.ListSandboxes(ctx)
	require.NoError(t, err)
	assert.Len(t, infos, sandboxCount-1)
	
	// Test shutdown
	err = manager.Shutdown(ctx)
	require.NoError(t, err)
	
	// Verify all sandboxes are cleaned up
	infos, err = manager.ListSandboxes(ctx)
	require.NoError(t, err)
	assert.Len(t, infos, 0)
}

// TestSandboxManagerMetrics tests metrics aggregation
func TestSandboxManagerMetrics(t *testing.T) {
	ctx := context.Background()
	mockPool := NewMockSandboxPool(5)
	manager := &DefaultSandboxManager{
		pool:      mockPool,
		sandboxes: make(map[string]Sandbox),
	}
	
	// Create test sandboxes
	for i := 0; i < 3; i++ {
		config := SandboxConfig{VMID: "metrics-test-" + string(rune(i))}
		_, err := manager.CreateSandbox(ctx, config)
		require.NoError(t, err)
	}
	
	// Get aggregated metrics
	metrics, err := manager.GetMetrics(ctx)
	require.NoError(t, err)
	assert.NotNil(t, metrics)
	
	// Get sandbox stats
	stats, err := manager.GetSandboxStats(ctx)
	require.NoError(t, err)
	assert.Equal(t, 3, stats.TotalSandboxes)
	assert.NotNil(t, stats.SandboxesByState)
	assert.NotNil(t, stats.PoolStats)
}

// TestSandboxManagerHealthCheck tests health checking functionality
func TestSandboxManagerHealthCheck(t *testing.T) {
	ctx := context.Background()
	mockPool := NewMockSandboxPool(5)
	manager := &DefaultSandboxManager{
		pool:      mockPool,
		sandboxes: make(map[string]Sandbox),
	}
	
	// Create healthy sandbox
	config := SandboxConfig{VMID: "healthy-sandbox"}
	sandbox, err := manager.CreateSandbox(ctx, config)
	require.NoError(t, err)
	
	// Health check should pass
	err = manager.HealthCheck(ctx)
	assert.NoError(t, err)
	
	// Destroy sandbox to make it unhealthy
	err = sandbox.Destroy(ctx)
	require.NoError(t, err)
	
	// Health check should detect and clean up unhealthy sandbox
	err = manager.HealthCheck(ctx)
	assert.Error(t, err) // Should report unhealthy sandboxes were found and cleaned
	assert.Contains(t, err.Error(), "unhealthy sandboxes")
	
	// Verify sandbox was removed from tracking
	infos, err := manager.ListSandboxes(ctx)
	require.NoError(t, err)
	assert.Len(t, infos, 0)
}

// TestSandboxManagerErrorHandling tests error scenarios
func TestSandboxManagerErrorHandling(t *testing.T) {
	ctx := context.Background()
	mockPool := NewMockSandboxPool(5)
	manager := &DefaultSandboxManager{
		pool:      mockPool,
		sandboxes: make(map[string]Sandbox),
	}
	
	// Test getting non-existent sandbox
	_, err := manager.GetSandbox(ctx, "non-existent")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
	
	// Test destroying non-existent sandbox
	err = manager.DestroySandbox(ctx, "non-existent")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
	
	// Test operations after shutdown
	err = manager.Shutdown(ctx)
	require.NoError(t, err)
	
	// Manager should still handle operations gracefully after shutdown
	infos, err := manager.ListSandboxes(ctx)
	require.NoError(t, err)
	assert.Len(t, infos, 0)
}

// BenchmarkManagerOperations benchmarks manager operations
func BenchmarkManagerOperations(b *testing.B) {
	ctx := context.Background()
	mockPool := NewMockSandboxPool(100)
	manager := &DefaultSandboxManager{
		pool:      mockPool,
		sandboxes: make(map[string]Sandbox),
	}
	
	b.Run("CreateSandbox", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			config := SandboxConfig{VMID: "bench-create"}
			sandbox, err := manager.CreateSandbox(ctx, config)
			if err != nil {
				b.Fatal(err)
			}
			
			// Clean up immediately to avoid memory issues
			_ = manager.ReleaseSandbox(ctx, sandbox)
		}
	})
	
	// Create sandboxes for other benchmarks
	sandboxes := make([]Sandbox, 10)
	for i := 0; i < 10; i++ {
		config := SandboxConfig{VMID: "bench-sandbox"}
		sandbox, err := manager.CreateSandbox(ctx, config)
		if err != nil {
			b.Fatal(err)
		}
		sandboxes[i] = sandbox
	}
	
	b.Run("ListSandboxes", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, err := manager.ListSandboxes(ctx)
			if err != nil {
				b.Fatal(err)
			}
		}
	})
	
	b.Run("GetSandbox", func(b *testing.B) {
		sandboxID := sandboxes[0].ID()
		for i := 0; i < b.N; i++ {
			_, err := manager.GetSandbox(ctx, sandboxID)
			if err != nil {
				b.Fatal(err)
			}
		}
	})
	
	b.Run("GetMetrics", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, err := manager.GetMetrics(ctx)
			if err != nil {
				b.Fatal(err)
			}
		}
	})
}

// TestSandboxManagerConcurrency tests concurrent manager operations
func TestSandboxManagerConcurrency(t *testing.T) {
	ctx := context.Background()
	mockPool := NewMockSandboxPool(20)
	manager := &DefaultSandboxManager{
		pool:      mockPool,
		sandboxes: make(map[string]Sandbox),
	}
	
	const numWorkers = 5
	const operationsPerWorker = 20
	
	// Channel to collect any errors
	errors := make(chan error, numWorkers*operationsPerWorker)
	
	// Start concurrent workers
	for i := 0; i < numWorkers; i++ {
		go func(workerID int) {
			for j := 0; j < operationsPerWorker; j++ {
				config := SandboxConfig{VMID: "concurrent-test"}
				
				// Create sandbox
				sandbox, err := manager.CreateSandbox(ctx, config)
				if err != nil {
					errors <- err
					return
				}
				
				// Get sandbox info
				_, err = manager.GetSandbox(ctx, sandbox.ID())
				if err != nil {
					errors <- err
					return
				}
				
				// Release sandbox
				err = manager.ReleaseSandbox(ctx, sandbox)
				if err != nil {
					errors <- err
					return
				}
			}
		}(i)
	}
	
	// Wait a bit for operations to complete
	time.Sleep(100 * time.Millisecond)
	
	// Check for errors
	close(errors)
	for err := range errors {
		t.Errorf("Concurrent operation failed: %v", err)
	}
	
	// Verify manager state is consistent
	infos, err := manager.ListSandboxes(ctx)
	require.NoError(t, err)
	
	// Should have no tracked sandboxes since all were released
	assert.Empty(t, infos)
}