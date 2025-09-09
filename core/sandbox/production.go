// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

package sandbox

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/sirupsen/logrus"
)

// HealthChecker provides health check functionality for sandboxes
type HealthChecker struct {
	manager *DefaultSandboxManager
	logger  *logrus.Entry
	metrics *HealthMetrics
	mu      sync.RWMutex
}

// HealthMetrics tracks health check statistics
type HealthMetrics struct {
	TotalChecks     int64     `json:"total_checks"`
	HealthyCount    int64     `json:"healthy_count"`
	UnhealthyCount  int64     `json:"unhealthy_count"`
	LastCheckTime   time.Time `json:"last_check_time"`
	AverageCheckTime time.Duration `json:"average_check_time"`
	ErrorRate       float64   `json:"error_rate"`
}

// NewHealthChecker creates a new health checker
func NewHealthChecker(manager *DefaultSandboxManager) *HealthChecker {
	return &HealthChecker{
		manager: manager,
		logger: logrus.WithField("component", "health-checker"),
		metrics: &HealthMetrics{},
	}
}

// CheckHealth performs comprehensive health check on all sandboxes
func (hc *HealthChecker) CheckHealth(ctx context.Context) (*HealthReport, error) {
	startTime := time.Now()
	
	atomic.AddInt64(&hc.metrics.TotalChecks, 1)
	
	hc.logger.Debug("Starting health check")
	
	// Get all sandboxes
	sandboxes, err := hc.manager.ListSandboxes(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to list sandboxes: %w", err)
	}
	
	report := &HealthReport{
		TotalSandboxes: len(sandboxes),
		HealthySandboxes: 0,
		UnhealthySandboxes: 0,
		CheckTime: startTime,
		Details: make(map[string]SandboxHealthDetail),
	}
	
	// Check each sandbox
	for _, info := range sandboxes {
		detail := hc.checkSandboxHealth(ctx, info)
		report.Details[info.ID] = detail
		
		if detail.Healthy {
			report.HealthySandboxes++
			atomic.AddInt64(&hc.metrics.HealthyCount, 1)
		} else {
			report.UnhealthySandboxes++
			atomic.AddInt64(&hc.metrics.UnhealthyCount, 1)
		}
	}
	
	// Update metrics
	checkDuration := time.Since(startTime)
	hc.updateMetrics(checkDuration)
	report.Duration = checkDuration
	
	// Calculate overall health
	if report.TotalSandboxes > 0 {
		report.HealthPercentage = float64(report.HealthySandboxes) / float64(report.TotalSandboxes) * 100
	}
	
	hc.logger.WithFields(logrus.Fields{
		"total": report.TotalSandboxes,
		"healthy": report.HealthySandboxes,
		"unhealthy": report.UnhealthySandboxes,
		"health_percentage": report.HealthPercentage,
		"duration": checkDuration,
	}).Info("Health check completed")
	
	return report, nil
}

// checkSandboxHealth checks health of individual sandbox
func (hc *HealthChecker) checkSandboxHealth(ctx context.Context, info *SandboxInfo) SandboxHealthDetail {
	detail := SandboxHealthDetail{
		ID: info.ID,
		Healthy: true,
		Issues: []string{},
	}
	
	// Check sandbox state
	switch info.State {
	case StateError, StateDestroyed:
		detail.Healthy = false
		detail.Issues = append(detail.Issues, fmt.Sprintf("Invalid state: %s", info.State))
	case StateStopped:
		detail.Issues = append(detail.Issues, "Sandbox is stopped")
	}
	
	// Check resource usage
	if info.Metrics.PeakMemoryUsed > int64(info.Config.MemoryMB)*1024*1024*2 {
		detail.Issues = append(detail.Issues, "High memory usage detected")
	}
	
	// Check error rate
	if info.Metrics.ErrorCount > 10 {
		detail.Healthy = false
		detail.Issues = append(detail.Issues, "High error count")
	}
	
	// Check last activity
	if time.Since(info.LastUsedAt) > 30*time.Minute {
		detail.Issues = append(detail.Issues, "Long idle time")
	}
	
	return detail
}

// updateMetrics updates health check metrics
func (hc *HealthChecker) updateMetrics(checkDuration time.Duration) {
	hc.mu.Lock()
	defer hc.mu.Unlock()
	
	hc.metrics.LastCheckTime = time.Now()
	
	// Update average check time
	totalChecks := atomic.LoadInt64(&hc.metrics.TotalChecks)
	if hc.metrics.AverageCheckTime == 0 {
		hc.metrics.AverageCheckTime = checkDuration
	} else {
		// Rolling average
		hc.metrics.AverageCheckTime = time.Duration(
			(int64(hc.metrics.AverageCheckTime)*totalChecks + int64(checkDuration)) / (totalChecks + 1),
		)
	}
	
	// Update error rate
	healthyCount := atomic.LoadInt64(&hc.metrics.HealthyCount)
	unhealthyCount := atomic.LoadInt64(&hc.metrics.UnhealthyCount)
	totalSandboxChecks := healthyCount + unhealthyCount
	
	if totalSandboxChecks > 0 {
		hc.metrics.ErrorRate = float64(unhealthyCount) / float64(totalSandboxChecks)
	}
}

// GetMetrics returns current health metrics
func (hc *HealthChecker) GetMetrics() *HealthMetrics {
	hc.mu.RLock()
	defer hc.mu.RUnlock()
	
	// Return a copy to avoid race conditions
	return &HealthMetrics{
		TotalChecks:      atomic.LoadInt64(&hc.metrics.TotalChecks),
		HealthyCount:     atomic.LoadInt64(&hc.metrics.HealthyCount),
		UnhealthyCount:   atomic.LoadInt64(&hc.metrics.UnhealthyCount),
		LastCheckTime:    hc.metrics.LastCheckTime,
		AverageCheckTime: hc.metrics.AverageCheckTime,
		ErrorRate:        hc.metrics.ErrorRate,
	}
}

// HealthReport contains results of health check
type HealthReport struct {
	TotalSandboxes     int                         `json:"total_sandboxes"`
	HealthySandboxes   int                         `json:"healthy_sandboxes"`
	UnhealthySandboxes int                         `json:"unhealthy_sandboxes"`
	HealthPercentage   float64                     `json:"health_percentage"`
	CheckTime          time.Time                   `json:"check_time"`
	Duration           time.Duration               `json:"duration"`
	Details            map[string]SandboxHealthDetail `json:"details"`
}

// SandboxHealthDetail contains health information for individual sandbox
type SandboxHealthDetail struct {
	ID      string   `json:"id"`
	Healthy bool     `json:"healthy"`
	Issues  []string `json:"issues"`
}

// RetryConfig configures retry behavior
type RetryConfig struct {
	MaxRetries      int           `json:"max_retries"`
	InitialDelay    time.Duration `json:"initial_delay"`
	BackoffFactor   float64       `json:"backoff_factor"`
	MaxDelay        time.Duration `json:"max_delay"`
	RetryableErrors []string      `json:"retryable_errors"`
}

// DefaultRetryConfig returns sensible retry defaults
func DefaultRetryConfig() RetryConfig {
	return RetryConfig{
		MaxRetries:    3,
		InitialDelay:  100 * time.Millisecond,
		BackoffFactor: 2.0,
		MaxDelay:      5 * time.Second,
		RetryableErrors: []string{
			"connection refused",
			"timeout",
			"temporary failure",
			"resource temporarily unavailable",
		},
	}
}

// RetryableOperation represents an operation that can be retried
type RetryableOperation func() error

// WithRetry executes an operation with exponential backoff retry
func WithRetry(ctx context.Context, config RetryConfig, operation RetryableOperation) error {
	var lastErr error
	delay := config.InitialDelay
	
	for attempt := 0; attempt <= config.MaxRetries; attempt++ {
		// Execute operation
		if err := operation(); err == nil {
			return nil // Success
		} else {
			lastErr = err
			
			// Check if error is retryable
			if !isRetryableError(err, config.RetryableErrors) {
				return err // Not retryable
			}
			
			// Don't delay on the last attempt
			if attempt == config.MaxRetries {
				break
			}
			
			// Wait before retrying
			select {
			case <-time.After(delay):
				// Calculate next delay with exponential backoff
				delay = time.Duration(float64(delay) * config.BackoffFactor)
				if delay > config.MaxDelay {
					delay = config.MaxDelay
				}
			case <-ctx.Done():
				return ctx.Err()
			}
		}
	}
	
	return fmt.Errorf("operation failed after %d attempts: %w", config.MaxRetries+1, lastErr)
}

// isRetryableError checks if an error should be retried
func isRetryableError(err error, retryableErrors []string) bool {
	errStr := err.Error()
	for _, retryable := range retryableErrors {
		if contains(errStr, retryable) {
			return true
		}
	}
	return false
}

// contains checks if a string contains a substring (case-insensitive)
func contains(s, substr string) bool {
	return len(s) >= len(substr) && 
		   (s == substr || 
		    (len(s) > len(substr) && 
		     (s[:len(substr)] == substr || 
		      s[len(s)-len(substr):] == substr || 
		      containsMiddle(s, substr))))
}

// containsMiddle checks if substr is in the middle of s
func containsMiddle(s, substr string) bool {
	for i := 1; i <= len(s)-len(substr)-1; i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// CircuitBreaker implements circuit breaker pattern for fault tolerance
type CircuitBreaker struct {
	maxFailures    int
	resetTimeout   time.Duration
	failures       int64
	lastFailureTime time.Time
	state          CircuitState
	mu             sync.RWMutex
	logger         *logrus.Entry
}

// CircuitState represents circuit breaker state
type CircuitState int

const (
	StateClosed CircuitState = iota
	StateOpen
	StateHalfOpen
)

// NewCircuitBreaker creates a new circuit breaker
func NewCircuitBreaker(maxFailures int, resetTimeout time.Duration) *CircuitBreaker {
	return &CircuitBreaker{
		maxFailures:  maxFailures,
		resetTimeout: resetTimeout,
		state:        StateClosed,
		logger:       logrus.WithField("component", "circuit-breaker"),
	}
}

// Execute runs an operation through the circuit breaker
func (cb *CircuitBreaker) Execute(operation func() error) error {
	cb.mu.Lock()
	defer cb.mu.Unlock()
	
	// Check if circuit should transition from Open to HalfOpen
	if cb.state == StateOpen && time.Since(cb.lastFailureTime) > cb.resetTimeout {
		cb.state = StateHalfOpen
		cb.logger.Info("Circuit breaker transitioning to half-open")
	}
	
	// If circuit is open, reject immediately
	if cb.state == StateOpen {
		return fmt.Errorf("circuit breaker is open")
	}
	
	// Execute operation
	err := operation()
	
	if err != nil {
		cb.failures++
		cb.lastFailureTime = time.Now()
		
		// Transition to open if failure threshold reached
		if cb.failures >= int64(cb.maxFailures) {
			cb.state = StateOpen
			cb.logger.WithField("failures", cb.failures).Warn("Circuit breaker opened due to failures")
		} else if cb.state == StateHalfOpen {
			cb.state = StateOpen
			cb.logger.Info("Circuit breaker returned to open state")
		}
		
		return err
	}
	
	// Success - reset if we were in half-open or closed state
	if cb.state == StateHalfOpen {
		cb.state = StateClosed
		cb.failures = 0
		cb.logger.Info("Circuit breaker closed after successful operation")
	} else if cb.state == StateClosed && cb.failures > 0 {
		cb.failures = 0 // Reset failure count on success
	}
	
	return nil
}

// GetState returns current circuit breaker state
func (cb *CircuitBreaker) GetState() CircuitState {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	return cb.state
}

// GetFailures returns current failure count
func (cb *CircuitBreaker) GetFailures() int64 {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	return cb.failures
}