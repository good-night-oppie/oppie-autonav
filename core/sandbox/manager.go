// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

package sandbox

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
)

// DefaultSandboxManager implements SandboxManager interface
type DefaultSandboxManager struct {
	pool       SandboxPool
	sandboxes  map[string]Sandbox
	mu         sync.RWMutex
	logger     *logrus.Entry
}

// NewSandboxManager creates a new sandbox manager
func NewSandboxManager(poolSize int, template SandboxConfig) *DefaultSandboxManager {
	pool := NewFirecrackerPool(poolSize, template)
	
	return &DefaultSandboxManager{
		pool:      pool,
		sandboxes: make(map[string]Sandbox),
		logger: logrus.WithFields(logrus.Fields{
			"component": "sandbox-manager",
			"pool_size": poolSize,
		}),
	}
}

// CreateSandbox creates a new sandbox with specified config
func (m *DefaultSandboxManager) CreateSandbox(ctx context.Context, config SandboxConfig) (Sandbox, error) {
	startTime := time.Now()
	
	sandbox, err := m.pool.Acquire(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("failed to acquire sandbox from pool: %w", err)
	}
	
	m.mu.Lock()
	m.sandboxes[sandbox.ID()] = sandbox
	m.mu.Unlock()
	
	m.logger.WithFields(logrus.Fields{
		"sandbox_id":    sandbox.ID(),
		"creation_time": time.Since(startTime),
	}).Info("Created new sandbox")
	
	return sandbox, nil
}

// GetSandbox retrieves an existing sandbox by ID
func (m *DefaultSandboxManager) GetSandbox(ctx context.Context, id string) (Sandbox, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	sandbox, exists := m.sandboxes[id]
	if !exists {
		return nil, fmt.Errorf("sandbox %s not found", id)
	}
	
	return sandbox, nil
}

// ListSandboxes returns all managed sandboxes
func (m *DefaultSandboxManager) ListSandboxes(ctx context.Context) ([]*SandboxInfo, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	infos := make([]*SandboxInfo, 0, len(m.sandboxes))
	
	for _, sandbox := range m.sandboxes {
		info, err := sandbox.GetInfo(ctx)
		if err != nil {
			m.logger.WithError(err).WithField("sandbox_id", sandbox.ID()).Warn("Failed to get sandbox info")
			continue
		}
		infos = append(infos, info)
	}
	
	return infos, nil
}

// GetPool returns the sandbox pool
func (m *DefaultSandboxManager) GetPool() SandboxPool {
	return m.pool
}

// GetMetrics returns aggregated metrics across all sandboxes
func (m *DefaultSandboxManager) GetMetrics(ctx context.Context) (*SandboxMetrics, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	var aggregated SandboxMetrics
	count := 0
	
	for _, sandbox := range m.sandboxes {
		info, err := sandbox.GetInfo(ctx)
		if err != nil {
			continue
		}
		
		metrics := info.Metrics
		
		// Aggregate timing metrics (averages)
		aggregated.VMStartupTime += metrics.VMStartupTime
		aggregated.SnapshotTime += metrics.SnapshotTime
		aggregated.RestoreTime += metrics.RestoreTime
		aggregated.ExecutionTime += metrics.ExecutionTime
		
		// Sum memory and CPU metrics
		aggregated.TotalMemoryUsed += metrics.TotalMemoryUsed
		if metrics.PeakMemoryUsed > aggregated.PeakMemoryUsed {
			aggregated.PeakMemoryUsed = metrics.PeakMemoryUsed
		}
		aggregated.CPUUtilization += metrics.CPUUtilization
		
		// Sum network metrics
		aggregated.NetworkBytesIn += metrics.NetworkBytesIn
		aggregated.NetworkBytesOut += metrics.NetworkBytesOut
		
		// Sum error and restart counts
		aggregated.ErrorCount += metrics.ErrorCount
		aggregated.RestartCount += metrics.RestartCount
		
		count++
	}
	
	// Calculate averages for timing metrics
	if count > 0 {
		aggregated.VMStartupTime /= time.Duration(count)
		aggregated.SnapshotTime /= time.Duration(count)
		aggregated.RestoreTime /= time.Duration(count)
		aggregated.ExecutionTime /= time.Duration(count)
		aggregated.CPUUtilization /= float64(count)
	}
	
	return &aggregated, nil
}

// ReleaseSandbox returns a sandbox to the pool and removes it from tracking
func (m *DefaultSandboxManager) ReleaseSandbox(ctx context.Context, sandbox Sandbox) error {
	m.mu.Lock()
	delete(m.sandboxes, sandbox.ID())
	m.mu.Unlock()
	
	if err := m.pool.Release(ctx, sandbox); err != nil {
		return fmt.Errorf("failed to release sandbox to pool: %w", err)
	}
	
	m.logger.WithField("sandbox_id", sandbox.ID()).Debug("Released sandbox back to pool")
	return nil
}

// DestroySandbox permanently destroys a sandbox
func (m *DefaultSandboxManager) DestroySandbox(ctx context.Context, id string) error {
	m.mu.Lock()
	sandbox, exists := m.sandboxes[id]
	if !exists {
		m.mu.Unlock()
		return fmt.Errorf("sandbox %s not found", id)
	}
	delete(m.sandboxes, id)
	m.mu.Unlock()
	
	if err := sandbox.Destroy(ctx); err != nil {
		return fmt.Errorf("failed to destroy sandbox: %w", err)
	}
	
	m.logger.WithField("sandbox_id", id).Info("Destroyed sandbox")
	return nil
}

// Shutdown gracefully shuts down all sandboxes and resources
func (m *DefaultSandboxManager) Shutdown(ctx context.Context) error {
	m.logger.Info("Shutting down sandbox manager")
	
	// Destroy all managed sandboxes
	m.mu.Lock()
	for id, sandbox := range m.sandboxes {
		if err := sandbox.Destroy(ctx); err != nil {
			m.logger.WithError(err).WithField("sandbox_id", id).Warn("Failed to destroy sandbox during shutdown")
		}
	}
	m.sandboxes = make(map[string]Sandbox)
	m.mu.Unlock()
	
	// Shutdown the pool
	if err := m.pool.Shutdown(ctx); err != nil {
		return fmt.Errorf("failed to shutdown sandbox pool: %w", err)
	}
	
	m.logger.Info("Sandbox manager shutdown completed")
	return nil
}

// HealthCheck performs health checks on all managed sandboxes
func (m *DefaultSandboxManager) HealthCheck(ctx context.Context) error {
	m.mu.RLock()
	sandboxes := make([]Sandbox, 0, len(m.sandboxes))
	for _, sandbox := range m.sandboxes {
		sandboxes = append(sandboxes, sandbox)
	}
	m.mu.RUnlock()
	
	unhealthyCount := 0
	
	for _, sandbox := range sandboxes {
		info, err := sandbox.GetInfo(ctx)
		if err != nil || info.State == StateError {
			unhealthyCount++
			m.logger.WithField("sandbox_id", sandbox.ID()).Warn("Unhealthy sandbox detected")
			
			// Attempt to destroy unhealthy sandbox
			if destroyErr := m.DestroySandbox(ctx, sandbox.ID()); destroyErr != nil {
				m.logger.WithError(destroyErr).WithField("sandbox_id", sandbox.ID()).Error("Failed to destroy unhealthy sandbox")
			}
		}
	}
	
	if unhealthyCount > 0 {
		return fmt.Errorf("%d unhealthy sandboxes detected and cleaned up", unhealthyCount)
	}
	
	return nil
}

// GetSandboxStats returns detailed statistics about sandbox usage
type SandboxStats struct {
	TotalSandboxes     int                    `json:"total_sandboxes"`
	SandboxesByState   map[SandboxState]int   `json:"sandboxes_by_state"`
	AverageStartupTime time.Duration          `json:"average_startup_time"`
	AverageMemoryUsage int64                  `json:"average_memory_usage"`
	TotalExecutions    int64                  `json:"total_executions"`
	SuccessRate        float64                `json:"success_rate"`
	PoolStats          *PoolStats             `json:"pool_stats"`
}

// GetSandboxStats returns detailed statistics about sandbox usage
func (m *DefaultSandboxManager) GetSandboxStats(ctx context.Context) (*SandboxStats, error) {
	infos, err := m.ListSandboxes(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to list sandboxes: %w", err)
	}
	
	stats := &SandboxStats{
		TotalSandboxes:   len(infos),
		SandboxesByState: make(map[SandboxState]int),
	}
	
	var totalStartupTime time.Duration
	var totalMemoryUsage int64
	var totalExecutions int64
	var totalErrors int
	
	for _, info := range infos {
		stats.SandboxesByState[info.State]++
		totalStartupTime += info.Metrics.VMStartupTime
		totalMemoryUsage += info.Metrics.TotalMemoryUsed
		totalExecutions++
		totalErrors += info.Metrics.ErrorCount
	}
	
	if len(infos) > 0 {
		stats.AverageStartupTime = totalStartupTime / time.Duration(len(infos))
		stats.AverageMemoryUsage = totalMemoryUsage / int64(len(infos))
	}
	
	if totalExecutions > 0 {
		stats.SuccessRate = float64(totalExecutions - int64(totalErrors)) / float64(totalExecutions)
	}
	
	// Get pool stats
	poolStats, err := m.pool.GetPoolStats(ctx)
	if err != nil {
		m.logger.WithError(err).Warn("Failed to get pool stats")
	} else {
		stats.PoolStats = poolStats
	}
	
	return stats, nil
}