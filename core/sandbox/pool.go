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

// FirecrackerPool implements SandboxPool for managing Firecracker VMs
type FirecrackerPool struct {
	maxSize         int
	available       chan Sandbox
	active          map[string]Sandbox
	template        SandboxConfig
	metrics         PoolStats
	mu              sync.RWMutex
	logger          *logrus.Entry
	shutdownCtx     context.Context
	shutdownCancel  context.CancelFunc
	backgroundTasks sync.WaitGroup
}

// NewFirecrackerPool creates a new Firecracker sandbox pool
func NewFirecrackerPool(maxSize int, template SandboxConfig) *FirecrackerPool {
	ctx, cancel := context.WithCancel(context.Background())
	
	pool := &FirecrackerPool{
		maxSize:        maxSize,
		available:      make(chan Sandbox, maxSize),
		active:         make(map[string]Sandbox),
		template:       template,
		shutdownCtx:    ctx,
		shutdownCancel: cancel,
		logger: logrus.WithFields(logrus.Fields{
			"component": "firecracker-pool",
			"max_size":  maxSize,
		}),
	}

	pool.metrics.TotalCapacity = maxSize

	// Start background maintenance
	pool.backgroundTasks.Add(1)
	go pool.maintenanceLoop()

	return pool
}

// Acquire gets an available sandbox from the pool
func (p *FirecrackerPool) Acquire(ctx context.Context, config SandboxConfig) (Sandbox, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	// Try to get from available pool first
	select {
	case sandbox := <-p.available:
		p.active[sandbox.ID()] = sandbox
		p.metrics.AvailableCount--
		p.metrics.ActiveCount++
		
		p.logger.WithField("sandbox_id", sandbox.ID()).Debug("Acquired sandbox from pool")
		return sandbox, nil
		
	default:
		// No available sandbox, create new one if under capacity
		if len(p.active) < p.maxSize {
			return p.createNewSandbox(config)
		}
		
		// Pool is at capacity, wait for available sandbox
		select {
		case sandbox := <-p.available:
			p.active[sandbox.ID()] = sandbox
			p.metrics.AvailableCount--
			p.metrics.ActiveCount++
			
			p.logger.WithField("sandbox_id", sandbox.ID()).Debug("Acquired sandbox from pool after wait")
			return sandbox, nil
			
		case <-ctx.Done():
			return nil, fmt.Errorf("timeout waiting for available sandbox: %w", ctx.Err())
		}
	}
}

// createNewSandbox creates a new sandbox instance
func (p *FirecrackerPool) createNewSandbox(config SandboxConfig) (Sandbox, error) {
	startTime := time.Now()
	
	// Use template config as base and override with requested config
	mergedConfig := p.template
	if config.MemoryMB > 0 {
		mergedConfig.MemoryMB = config.MemoryMB
	}
	if config.CPUCount > 0 {
		mergedConfig.CPUCount = config.CPUCount
	}
	if config.TimeoutSeconds > 0 {
		mergedConfig.TimeoutSeconds = config.TimeoutSeconds
	}
	if config.VMID != "" {
		mergedConfig.VMID = config.VMID
	}
	
	sandbox, err := NewFirecrackerSandbox(mergedConfig)
	if err != nil {
		p.metrics.ErrorRate = p.calculateErrorRate()
		return nil, fmt.Errorf("failed to create new sandbox: %w", err)
	}
	
	creationTime := time.Since(startTime)
	p.updateAverageStartupTime(creationTime)
	
	p.active[sandbox.ID()] = sandbox
	p.metrics.CreatedCount++
	p.metrics.ActiveCount++
	
	p.logger.WithFields(logrus.Fields{
		"sandbox_id":    sandbox.ID(),
		"creation_time": creationTime,
	}).Info("Created new sandbox")
	
	return sandbox, nil
}

// Release returns a sandbox to the pool for reuse
func (p *FirecrackerPool) Release(ctx context.Context, sandbox Sandbox) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	sandboxID := sandbox.ID()
	
	// Remove from active list
	delete(p.active, sandboxID)
	p.metrics.ActiveCount--
	
	// Check if sandbox is still healthy
	info, err := sandbox.GetInfo(ctx)
	if err != nil || info.State == StateError {
		// Destroy unhealthy sandbox
		if destroyErr := sandbox.Destroy(ctx); destroyErr != nil {
			p.logger.WithError(destroyErr).WithField("sandbox_id", sandboxID).Warn("Failed to destroy unhealthy sandbox")
		}
		p.metrics.DestroyedCount++
		
		p.logger.WithField("sandbox_id", sandboxID).Debug("Destroyed unhealthy sandbox instead of returning to pool")
		return nil
	}
	
	// Reset sandbox state for reuse
	if err := p.resetSandbox(ctx, sandbox); err != nil {
		// If reset fails, destroy the sandbox
		if destroyErr := sandbox.Destroy(ctx); destroyErr != nil {
			p.logger.WithError(destroyErr).WithField("sandbox_id", sandboxID).Warn("Failed to destroy sandbox after reset failure")
		}
		p.metrics.DestroyedCount++
		return fmt.Errorf("failed to reset sandbox for reuse: %w", err)
	}
	
	// Return to pool if there's space
	select {
	case p.available <- sandbox:
		p.metrics.AvailableCount++
		p.logger.WithField("sandbox_id", sandboxID).Debug("Returned sandbox to pool")
		
	default:
		// Pool is full, destroy excess sandbox
		if err := sandbox.Destroy(ctx); err != nil {
			p.logger.WithError(err).WithField("sandbox_id", sandboxID).Warn("Failed to destroy excess sandbox")
		}
		p.metrics.DestroyedCount++
		p.logger.WithField("sandbox_id", sandboxID).Debug("Destroyed excess sandbox")
	}
	
	return nil
}

// resetSandbox prepares a sandbox for reuse
func (p *FirecrackerPool) resetSandbox(ctx context.Context, sandbox Sandbox) error {
	// Stop the sandbox to clean state
	if err := sandbox.Stop(ctx); err != nil {
		return fmt.Errorf("failed to stop sandbox: %w", err)
	}
	
	// TODO: Add more reset logic as needed:
	// - Clear temporary files
	// - Reset network state
	// - Clear logs
	
	return nil
}

// GetPoolStats returns pool utilization statistics
func (p *FirecrackerPool) GetPoolStats(ctx context.Context) (*PoolStats, error) {
	p.mu.RLock()
	defer p.mu.RUnlock()

	stats := p.metrics
	stats.PoolUtilization = float64(p.metrics.ActiveCount) / float64(p.metrics.TotalCapacity)
	
	return &stats, nil
}

// Cleanup removes unused sandboxes and resources
func (p *FirecrackerPool) Cleanup(ctx context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cleaned := 0
	
	// Clean up available sandboxes that haven't been used recently
	for {
		select {
		case sandbox := <-p.available:
			info, err := sandbox.GetInfo(ctx)
			if err != nil {
				continue
			}
			
			// Destroy sandboxes unused for more than 5 minutes
			if time.Since(info.LastUsedAt) > 5*time.Minute {
				if err := sandbox.Destroy(ctx); err != nil {
					p.logger.WithError(err).WithField("sandbox_id", sandbox.ID()).Warn("Failed to destroy unused sandbox during cleanup")
				} else {
					cleaned++
					p.metrics.DestroyedCount++
					p.metrics.AvailableCount--
				}
			} else {
				// Put back in pool if still fresh
				p.available <- sandbox
			}
			
		default:
			// No more available sandboxes
			goto done
		}
	}

done:
	p.logger.WithField("cleaned_count", cleaned).Info("Pool cleanup completed")
	return nil
}

// Shutdown gracefully shuts down the pool
func (p *FirecrackerPool) Shutdown(ctx context.Context) error {
	p.logger.Info("Shutting down sandbox pool")
	
	// Cancel background tasks
	p.shutdownCancel()
	p.backgroundTasks.Wait()
	
	p.mu.Lock()
	defer p.mu.Unlock()

	// Destroy all active sandboxes
	for id, sandbox := range p.active {
		if err := sandbox.Destroy(ctx); err != nil {
			p.logger.WithError(err).WithField("sandbox_id", id).Warn("Failed to destroy active sandbox during shutdown")
		}
	}
	p.active = make(map[string]Sandbox)
	p.metrics.ActiveCount = 0

	// Destroy all available sandboxes
	for {
		select {
		case sandbox := <-p.available:
			if err := sandbox.Destroy(ctx); err != nil {
				p.logger.WithError(err).WithField("sandbox_id", sandbox.ID()).Warn("Failed to destroy available sandbox during shutdown")
			}
			p.metrics.AvailableCount--
			
		default:
			goto done
		}
	}

done:
	close(p.available)
	p.logger.Info("Sandbox pool shutdown completed")
	return nil
}

// maintenanceLoop runs background maintenance tasks
func (p *FirecrackerPool) maintenanceLoop() {
	defer p.backgroundTasks.Done()
	
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			if err := p.performMaintenance(); err != nil {
				p.logger.WithError(err).Warn("Maintenance task failed")
			}
			
		case <-p.shutdownCtx.Done():
			return
		}
	}
}

// performMaintenance runs periodic maintenance tasks
func (p *FirecrackerPool) performMaintenance() error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	
	// Run cleanup
	if err := p.Cleanup(ctx); err != nil {
		return fmt.Errorf("cleanup failed: %w", err)
	}
	
	// Pre-warm pool if needed
	p.mu.RLock()
	availableCount := p.metrics.AvailableCount
	activeCount := p.metrics.ActiveCount
	p.mu.RUnlock()
	
	minAvailable := p.maxSize / 4 // Keep 25% pre-warmed
	if availableCount < minAvailable && (availableCount + activeCount) < p.maxSize {
		p.prewarmPool(ctx, minAvailable - availableCount)
	}
	
	return nil
}

// prewarmPool creates sandboxes to maintain minimum available count
func (p *FirecrackerPool) prewarmPool(ctx context.Context, count int) {
	for i := 0; i < count; i++ {
		sandbox, err := p.createNewSandbox(p.template)
		if err != nil {
			p.logger.WithError(err).Warn("Failed to create sandbox during prewarming")
			continue
		}
		
		// Remove from active and put in available pool
		p.mu.Lock()
		delete(p.active, sandbox.ID())
		p.metrics.ActiveCount--
		
		select {
		case p.available <- sandbox:
			p.metrics.AvailableCount++
		default:
			// Pool is full, destroy the sandbox
			if err := sandbox.Destroy(ctx); err != nil {
				p.logger.WithError(err).WithField("sandbox_id", sandbox.ID()).Warn("Failed to destroy excess prewarmed sandbox")
			}
			p.metrics.DestroyedCount++
		}
		p.mu.Unlock()
	}
	
	p.logger.WithField("prewarmed_count", count).Debug("Prewarmed pool with new sandboxes")
}

// updateAverageStartupTime updates the rolling average startup time
func (p *FirecrackerPool) updateAverageStartupTime(duration time.Duration) {
	// Simple rolling average with weight of 0.1 for new values
	if p.metrics.AverageStartupTime == 0 {
		p.metrics.AverageStartupTime = duration
	} else {
		p.metrics.AverageStartupTime = time.Duration(
			float64(p.metrics.AverageStartupTime)*0.9 + float64(duration)*0.1,
		)
	}
}

// calculateErrorRate calculates current error rate
func (p *FirecrackerPool) calculateErrorRate() float64 {
	if p.metrics.CreatedCount == 0 {
		return 0
	}
	return float64(p.metrics.ErrorCount) / float64(p.metrics.CreatedCount)
}