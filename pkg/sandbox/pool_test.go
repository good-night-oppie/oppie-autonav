// Copyright 2025 Good Night Oppie
// SPDX-License-Identifier: Apache-2.0

package sandbox

import (
	"context"
	"testing"
	"time"

	"github.com/firecracker-microvm/firecracker-go-sdk"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestVMPool_NewVMPool(t *testing.T) {
	tests := []struct {
		name    string
		config  VMPoolConfig
		wantErr bool
	}{
		{
			name: "valid_config",
			config: VMPoolConfig{
				MaxSize:        10,
				MinAvailable:   2,
				StartupTimeout: 30 * time.Second,
				PreWarmCount:   3,
				Template:       firecracker.Config{},
			},
			wantErr: false,
		},
		{
			name: "invalid_max_size",
			config: VMPoolConfig{
				MaxSize: 0,
			},
			wantErr: true,
		},
		{
			name: "invalid_min_available",
			config: VMPoolConfig{
				MaxSize:      10,
				MinAvailable: 15,
			},
			wantErr: true,
		},
		{
			name: "invalid_startup_timeout",
			config: VMPoolConfig{
				MaxSize:        10,
				StartupTimeout: 0,
			},
			wantErr: true,
		},
		{
			name: "invalid_pre_warm_count",
			config: VMPoolConfig{
				MaxSize:      10,
				PreWarmCount: 15,
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			pool, err := NewVMPool(ctx, tt.config)
			
			if tt.wantErr {
				assert.Error(t, err)
				assert.Nil(t, pool)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, pool)
				
				// Clean up
				if pool != nil {
					err := pool.Close()
					assert.NoError(t, err)
				}
			}
		})
	}
}

func TestVMPool_AcquireRelease(t *testing.T) {
	ctx := context.Background()
	config := VMPoolConfig{
		MaxSize:        5,
		MinAvailable:   1,
		StartupTimeout: 100 * time.Millisecond,
		PreWarmCount:   2,
		Template:       firecracker.Config{},
	}

	pool, err := NewVMPool(ctx, config)
	require.NoError(t, err)
	defer pool.Close()

	// Test acquiring VM
	vm, err := pool.AcquireVM(ctx)
	require.NoError(t, err)
	assert.NotNil(t, vm)
	assert.NotEmpty(t, vm.ID)
	assert.Equal(t, VMStateRunning, vm.State)
	assert.Equal(t, int64(1), vm.UseCount)

	// Verify pool stats
	stats := pool.Stats()
	assert.Equal(t, 1, stats.Available) // One pre-warmed VM remaining
	assert.Equal(t, 1, stats.Active)    // One VM active

	// Test releasing VM
	err = pool.ReleaseVM(vm)
	require.NoError(t, err)

	// Verify pool stats after release
	stats = pool.Stats()
	assert.Equal(t, 2, stats.Available) // VM returned to available pool
	assert.Equal(t, 0, stats.Active)    // No active VMs
}

func TestVMPool_ExhaustPool(t *testing.T) {
	ctx := context.Background()
	config := VMPoolConfig{
		MaxSize:        2,
		MinAvailable:   0,
		StartupTimeout: 50 * time.Millisecond,
		PreWarmCount:   2,
		Template:       firecracker.Config{},
	}

	pool, err := NewVMPool(ctx, config)
	require.NoError(t, err)
	defer pool.Close()

	// Acquire all available VMs
	vm1, err := pool.AcquireVM(ctx)
	require.NoError(t, err)
	
	vm2, err := pool.AcquireVM(ctx)
	require.NoError(t, err)

	// Verify pool is exhausted
	stats := pool.Stats()
	assert.Equal(t, 0, stats.Available)
	assert.Equal(t, 2, stats.Active)

	// Try to acquire one more VM - should timeout
	ctx, cancel := context.WithTimeout(ctx, 100*time.Millisecond)
	defer cancel()
	
	vm3, err := pool.AcquireVM(ctx)
	assert.Error(t, err)
	assert.Nil(t, vm3)

	// Release VMs
	err = pool.ReleaseVM(vm1)
	require.NoError(t, err)
	err = pool.ReleaseVM(vm2)
	require.NoError(t, err)
}

func TestVMPool_Close(t *testing.T) {
	ctx := context.Background()
	config := VMPoolConfig{
		MaxSize:        3,
		MinAvailable:   1,
		StartupTimeout: 30 * time.Second,
		PreWarmCount:   2,
		Template:       firecracker.Config{},
	}

	pool, err := NewVMPool(ctx, config)
	require.NoError(t, err)

	// Acquire a VM
	vm, err := pool.AcquireVM(ctx)
	require.NoError(t, err)

	// Close the pool
	err = pool.Close()
	require.NoError(t, err)

	// Verify pool is closed
	stats := pool.Stats()
	assert.True(t, stats.Closed)

	// Try to acquire VM from closed pool
	vm2, err := pool.AcquireVM(ctx)
	assert.Equal(t, ErrPoolClosed, err)
	assert.Nil(t, vm2)

	// Try to release VM to closed pool (should destroy it)
	err = pool.ReleaseVM(vm)
	require.NoError(t, err)
}

func TestVMPool_ConcurrentAccess(t *testing.T) {
	ctx := context.Background()
	config := VMPoolConfig{
		MaxSize:        10,
		MinAvailable:   2,
		StartupTimeout: 30 * time.Second,
		PreWarmCount:   5,
		Template:       firecracker.Config{},
	}

	pool, err := NewVMPool(ctx, config)
	require.NoError(t, err)
	defer pool.Close()

	const numGoroutines = 10
	const numOperations = 5

	// Channel to collect any errors
	errCh := make(chan error, numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		go func() {
			for j := 0; j < numOperations; j++ {
				// Acquire VM
				vm, err := pool.AcquireVM(ctx)
				if err != nil {
					errCh <- err
					return
				}

				// Simulate some work
				time.Sleep(time.Millisecond)

				// Release VM
				err = pool.ReleaseVM(vm)
				if err != nil {
					errCh <- err
					return
				}
			}
			errCh <- nil
		}()
	}

	// Wait for all goroutines to complete
	for i := 0; i < numGoroutines; i++ {
		select {
		case err := <-errCh:
			assert.NoError(t, err)
		case <-time.After(10 * time.Second):
			t.Fatal("Test timed out")
		}
	}

	// Verify final state
	stats := pool.Stats()
	assert.Equal(t, 0, stats.Active) // All VMs should be returned
	assert.False(t, stats.Closed)    // Pool should still be open
}

func TestVMPool_Stats(t *testing.T) {
	ctx := context.Background()
	config := VMPoolConfig{
		MaxSize:        5,
		MinAvailable:   1,
		StartupTimeout: 30 * time.Second,
		PreWarmCount:   3,
		Template:       firecracker.Config{},
	}

	pool, err := NewVMPool(ctx, config)
	require.NoError(t, err)
	defer pool.Close()

	// Initial stats
	stats := pool.Stats()
	assert.Equal(t, 5, stats.MaxSize)
	assert.Equal(t, 3, stats.Available)
	assert.Equal(t, 0, stats.Active)
	assert.Equal(t, 3, stats.Total)
	assert.False(t, stats.Closed)

	// Acquire some VMs
	vm1, err := pool.AcquireVM(ctx)
	require.NoError(t, err)
	
	vm2, err := pool.AcquireVM(ctx)
	require.NoError(t, err)

	// Stats after acquisition
	stats = pool.Stats()
	assert.Equal(t, 1, stats.Available)
	assert.Equal(t, 2, stats.Active)
	assert.Equal(t, 3, stats.Total)

	// Release one VM
	err = pool.ReleaseVM(vm1)
	require.NoError(t, err)

	// Stats after release
	stats = pool.Stats()
	assert.Equal(t, 2, stats.Available)
	assert.Equal(t, 1, stats.Active)
	assert.Equal(t, 3, stats.Total)

	// Clean up
	err = pool.ReleaseVM(vm2)
	require.NoError(t, err)
}

func TestValidateConfig(t *testing.T) {
	tests := []struct {
		name    string
		config  VMPoolConfig
		wantErr string
	}{
		{
			name: "valid_config",
			config: VMPoolConfig{
				MaxSize:        10,
				MinAvailable:   5,
				StartupTimeout: 30 * time.Second,
				PreWarmCount:   3,
			},
			wantErr: "",
		},
		{
			name: "zero_max_size",
			config: VMPoolConfig{
				MaxSize: 0,
			},
			wantErr: "max_size must be positive",
		},
		{
			name: "negative_min_available",
			config: VMPoolConfig{
				MaxSize:      10,
				MinAvailable: -1,
			},
			wantErr: "min_available must be between 0 and max_size",
		},
		{
			name: "min_available_exceeds_max",
			config: VMPoolConfig{
				MaxSize:      10,
				MinAvailable: 15,
			},
			wantErr: "min_available must be between 0 and max_size",
		},
		{
			name: "zero_startup_timeout",
			config: VMPoolConfig{
				MaxSize:        10,
				StartupTimeout: 0,
			},
			wantErr: "startup_timeout must be positive",
		},
		{
			name: "negative_pre_warm_count",
			config: VMPoolConfig{
				MaxSize:        10,
				MinAvailable:   2,
				StartupTimeout: 30 * time.Second,
				PreWarmCount:   -1,
			},
			wantErr: "pre_warm_count must be between 0 and max_size",
		},
		{
			name: "pre_warm_count_exceeds_max",
			config: VMPoolConfig{
				MaxSize:        10,
				MinAvailable:   2,
				StartupTimeout: 30 * time.Second,
				PreWarmCount:   15,
			},
			wantErr: "pre_warm_count must be between 0 and max_size",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateConfig(tt.config)
			
			if tt.wantErr == "" {
				assert.NoError(t, err)
			} else {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), tt.wantErr)
			}
		})
	}
}

func TestGenerateVMID(t *testing.T) {
	// Test that VM IDs are unique
	ids := make(map[string]bool)
	
	for i := 0; i < 1000; i++ {
		id := generateVMID()
		
		// Check format
		assert.Contains(t, id, "vm-")
		assert.True(t, len(id) > 20) // Should be vm- + timestamp + 8 random chars
		
		// Check uniqueness
		assert.False(t, ids[id], "Duplicate VM ID generated: %s", id)
		ids[id] = true
		
		// Small delay to ensure timestamp changes
		if i%100 == 0 {
			time.Sleep(time.Microsecond)
		}
	}
}