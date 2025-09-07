// Copyright 2025 Good Night Oppie
// SPDX-License-Identifier: Apache-2.0

// Package sandbox provides hot-loop MCTS sandbox infrastructure using Firecracker microVMs
// with integrated Helios state management for sub-100ms iteration times.
package sandbox

import (
	"context"
	"errors"
	"sync"
	"time"

	"github.com/firecracker-microvm/firecracker-go-sdk"
	"github.com/sirupsen/logrus"
)

var (
	ErrPoolClosed     = errors.New("pool is closed")
	ErrPoolExhausted  = errors.New("pool exhausted")
	ErrInvalidConfig  = errors.New("invalid pool configuration")
)

// VMPoolConfig defines configuration for the Firecracker VM pool
type VMPoolConfig struct {
	MaxSize       int           `json:"max_size"`        // Maximum VMs in pool
	MinAvailable  int           `json:"min_available"`   // Minimum available VMs to maintain
	StartupTimeout time.Duration `json:"startup_timeout"` // VM startup timeout
	Template      firecracker.Config `json:"template"`   // Template VM configuration
	PreWarmCount  int           `json:"pre_warm_count"`  // Number of VMs to pre-warm
}

// VMPool manages a pool of Firecracker microVMs for MCTS exploration
type VMPool struct {
	mu         sync.RWMutex
	config     VMPoolConfig
	available  chan *ManagedVM
	active     map[string]*ManagedVM
	closed     bool
	ctx        context.Context
	cancel     context.CancelFunc
	logger     *logrus.Logger
}

// ManagedVM wraps a Firecracker machine with management metadata
type ManagedVM struct {
	ID        string
	Machine   *firecracker.Machine
	Config    firecracker.Config
	CreatedAt time.Time
	LastUsed  time.Time
	UseCount  int64
	State     VMState
}

// VMState represents the current state of a managed VM
type VMState int

const (
	VMStateCreated VMState = iota
	VMStateRunning
	VMStatePaused
	VMStateStopped
	VMStateError
)

// NewVMPool creates a new Firecracker VM pool with the specified configuration
func NewVMPool(ctx context.Context, config VMPoolConfig) (*VMPool, error) {
	if err := validateConfig(config); err != nil {
		return nil, err
	}

	poolCtx, cancel := context.WithCancel(ctx)
	
	pool := &VMPool{
		config:    config,
		available: make(chan *ManagedVM, config.MaxSize),
		active:    make(map[string]*ManagedVM),
		ctx:       poolCtx,
		cancel:    cancel,
		logger:    logrus.New(),
	}

	// Pre-warm the pool
	if err := pool.preWarm(); err != nil {
		cancel()
		return nil, err
	}

	return pool, nil
}

// AcquireVM obtains an available VM from the pool
func (p *VMPool) AcquireVM(ctx context.Context) (*ManagedVM, error) {
	p.mu.RLock()
	if p.closed {
		p.mu.RUnlock()
		return nil, ErrPoolClosed
	}
	p.mu.RUnlock()

	select {
	case vm := <-p.available:
		p.mu.Lock()
		p.active[vm.ID] = vm
		vm.LastUsed = time.Now()
		vm.UseCount++
		vm.State = VMStateRunning
		p.mu.Unlock()
		
		p.logger.WithFields(logrus.Fields{
			"vm_id": vm.ID,
			"use_count": vm.UseCount,
		}).Debug("VM acquired from pool")
		
		return vm, nil
		
	case <-ctx.Done():
		return nil, ctx.Err()
		
	case <-time.After(p.config.StartupTimeout):
		return nil, ErrPoolExhausted
	}
}

// ReleaseVM returns a VM to the available pool
func (p *VMPool) ReleaseVM(vm *ManagedVM) error {
	if vm == nil {
		return errors.New("cannot release nil VM")
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	if p.closed {
		// If pool is closed, destroy the VM
		return p.destroyVM(vm)
	}

	// Remove from active map
	delete(p.active, vm.ID)
	
	// Reset VM state
	vm.State = VMStateCreated
	vm.LastUsed = time.Now()

	// Return to available pool
	select {
	case p.available <- vm:
		p.logger.WithField("vm_id", vm.ID).Debug("VM returned to pool")
		return nil
	default:
		// Pool is full, destroy the VM
		return p.destroyVM(vm)
	}
}

// Close shuts down the VM pool and destroys all VMs
func (p *VMPool) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.closed {
		return nil
	}

	p.closed = true
	p.cancel()

	// Destroy all available VMs
	close(p.available)
	for vm := range p.available {
		if err := p.destroyVM(vm); err != nil {
			p.logger.WithError(err).WithField("vm_id", vm.ID).Error("Failed to destroy available VM")
		}
	}

	// Destroy all active VMs
	for _, vm := range p.active {
		if err := p.destroyVM(vm); err != nil {
			p.logger.WithError(err).WithField("vm_id", vm.ID).Error("Failed to destroy active VM")
		}
	}

	p.logger.Info("VM pool closed")
	return nil
}

// Stats returns current pool statistics
func (p *VMPool) Stats() PoolStats {
	p.mu.RLock()
	defer p.mu.RUnlock()

	return PoolStats{
		MaxSize:   p.config.MaxSize,
		Available: len(p.available),
		Active:    len(p.active),
		Total:     len(p.available) + len(p.active),
		Closed:    p.closed,
	}
}

// PoolStats represents VM pool statistics
type PoolStats struct {
	MaxSize   int  `json:"max_size"`
	Available int  `json:"available"`
	Active    int  `json:"active"`
	Total     int  `json:"total"`
	Closed    bool `json:"closed"`
}

// preWarm creates initial VMs in the pool
func (p *VMPool) preWarm() error {
	for i := 0; i < p.config.PreWarmCount; i++ {
		vm, err := p.createVM()
		if err != nil {
			return err
		}
		
		select {
		case p.available <- vm:
			p.logger.WithField("vm_id", vm.ID).Debug("Pre-warmed VM added to pool")
		default:
			return errors.New("failed to add pre-warmed VM to pool")
		}
	}
	
	p.logger.WithField("count", p.config.PreWarmCount).Info("VM pool pre-warmed")
	return nil
}

// createVM creates a new managed VM
func (p *VMPool) createVM() (*ManagedVM, error) {
	config := p.config.Template
	
	// Create unique VM ID
	vmID := generateVMID()
	
	// Create Firecracker machine
	machine, err := firecracker.NewMachine(p.ctx, config)
	if err != nil {
		return nil, err
	}

	vm := &ManagedVM{
		ID:        vmID,
		Machine:   machine,
		Config:    config,
		CreatedAt: time.Now(),
		State:     VMStateCreated,
	}

	return vm, nil
}

// destroyVM safely destroys a managed VM
func (p *VMPool) destroyVM(vm *ManagedVM) error {
	if vm.Machine != nil {
		if err := vm.Machine.Shutdown(p.ctx); err != nil {
			p.logger.WithError(err).WithField("vm_id", vm.ID).Warn("Failed to shutdown VM gracefully")
		}
	}
	
	vm.State = VMStateStopped
	p.logger.WithField("vm_id", vm.ID).Debug("VM destroyed")
	return nil
}

// validateConfig validates the VM pool configuration
func validateConfig(config VMPoolConfig) error {
	if config.MaxSize <= 0 {
		return errors.New("max_size must be positive")
	}
	
	if config.MinAvailable < 0 || config.MinAvailable > config.MaxSize {
		return errors.New("min_available must be between 0 and max_size")
	}
	
	if config.StartupTimeout <= 0 {
		return errors.New("startup_timeout must be positive")
	}
	
	if config.PreWarmCount < 0 || config.PreWarmCount > config.MaxSize {
		return errors.New("pre_warm_count must be between 0 and max_size")
	}

	return nil
}

// generateVMID generates a unique VM identifier
func generateVMID() string {
	return "vm-" + time.Now().Format("20060102-150405-") + randString(8)
}

// randString generates a random string of specified length
func randString(n int) string {
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = charset[time.Now().UnixNano()%int64(len(charset))]
	}
	return string(b)
}