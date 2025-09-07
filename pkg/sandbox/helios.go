// Copyright 2025 Good Night Oppie
// SPDX-License-Identifier: Apache-2.0

// Package sandbox provides Helios integration for state management within VMs
package sandbox

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
)

// HeliosManager manages Helios state operations within VMs
type HeliosManager struct {
	workDir    string
	binaryPath string
	logger     *logrus.Logger
}

// HeliosConfig defines configuration for Helios integration
type HeliosConfig struct {
	WorkDir    string `json:"work_dir"`    // Working directory for Helios operations
	BinaryPath string `json:"binary_path"` // Path to helios-cli binary
}

// SnapshotMetrics contains performance metrics for snapshot operations
type SnapshotMetrics struct {
	CommitTime     time.Duration `json:"commit_time"`
	ObjectCount    int           `json:"object_count"`
	DedupRatio     float64       `json:"dedup_ratio"`
	StorageSize    int64         `json:"storage_size"`
	OperationTime  time.Time     `json:"operation_time"`
}

// NewHeliosManager creates a new Helios manager instance
func NewHeliosManager(config HeliosConfig) (*HeliosManager, error) {
	if config.BinaryPath == "" {
		return nil, fmt.Errorf("binary_path is required")
	}
	
	if config.WorkDir == "" {
		return nil, fmt.Errorf("work_dir is required")
	}

	// Check if binary exists and is executable
	if _, err := os.Stat(config.BinaryPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("helios-cli binary not found at %s", config.BinaryPath)
	}

	// Convert binary path to absolute path
	binaryPath, err := filepath.Abs(config.BinaryPath)
	if err != nil {
		return nil, fmt.Errorf("failed to get absolute binary path: %w", err)
	}

	// Ensure work directory exists
	if err := os.MkdirAll(config.WorkDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create work directory: %w", err)
	}

	hm := &HeliosManager{
		workDir:    config.WorkDir,
		binaryPath: binaryPath,
		logger:     logrus.New(),
	}

	return hm, nil
}

// Commit creates a snapshot of the current state
func (hm *HeliosManager) Commit(ctx context.Context, message string) (string, *SnapshotMetrics, error) {
	startTime := time.Now()
	
	cmd := exec.CommandContext(ctx, hm.binaryPath, "commit", "--work", hm.workDir)
	
	hm.logger.WithFields(logrus.Fields{
		"command": cmd.String(),
		"work_dir": hm.workDir,
		"message": message,
	}).Debug("Executing Helios commit")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", nil, fmt.Errorf("helios commit failed: %w, output: %s", err, string(output))
	}

	commitTime := time.Since(startTime)
	
	// Parse snapshot ID from JSON output
	outputStr := strings.TrimSpace(string(output))
	if outputStr == "" {
		return "", nil, fmt.Errorf("empty output returned")
	}
	
	// Extract actual snapshot ID from JSON response
	var snapshotResponse struct {
		SnapshotID string `json:"snapshot_id"`
	}
	
	if err := json.Unmarshal([]byte(outputStr), &snapshotResponse); err != nil {
		return "", nil, fmt.Errorf("failed to parse snapshot response: %w", err)
	}
	
	if snapshotResponse.SnapshotID == "" {
		return "", nil, fmt.Errorf("empty snapshot ID in response")
	}
	
	snapshotID := snapshotResponse.SnapshotID

	metrics := &SnapshotMetrics{
		CommitTime:    commitTime,
		OperationTime: startTime,
	}

	hm.logger.WithFields(logrus.Fields{
		"snapshot_id": snapshotID,
		"commit_time": commitTime,
	}).Info("Helios commit completed")

	return snapshotID, metrics, nil
}

// Restore restores state from a snapshot
func (hm *HeliosManager) Restore(ctx context.Context, snapshotID string) error {
	if snapshotID == "" {
		return fmt.Errorf("snapshot ID cannot be empty")
	}

	startTime := time.Now()
	
	cmd := exec.CommandContext(ctx, hm.binaryPath, "restore", "--id", snapshotID)
	cmd.Dir = hm.workDir
	
	hm.logger.WithFields(logrus.Fields{
		"command": cmd.String(),
		"snapshot_id": snapshotID,
	}).Debug("Executing Helios restore")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("helios restore failed: %w, output: %s", err, string(output))
	}

	restoreTime := time.Since(startTime)
	
	hm.logger.WithFields(logrus.Fields{
		"snapshot_id": snapshotID,
		"restore_time": restoreTime,
	}).Info("Helios restore completed")

	return nil
}

// Diff computes differences between two snapshots
func (hm *HeliosManager) Diff(ctx context.Context, fromID, toID string) (string, error) {
	if fromID == "" || toID == "" {
		return "", fmt.Errorf("both snapshot IDs are required for diff")
	}

	cmd := exec.CommandContext(ctx, hm.binaryPath, "diff", "--from", fromID, "--to", toID)
	cmd.Dir = hm.workDir
	
	hm.logger.WithFields(logrus.Fields{
		"command": cmd.String(),
		"from_id": fromID,
		"to_id": toID,
	}).Debug("Executing Helios diff")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("helios diff failed: %w, output: %s", err, string(output))
	}

	return string(output), nil
}

// Materialize extracts snapshot contents to a directory
func (hm *HeliosManager) Materialize(ctx context.Context, snapshotID, outputDir string, options MaterializeOptions) error {
	if snapshotID == "" {
		return fmt.Errorf("snapshot ID cannot be empty")
	}
	
	if outputDir == "" {
		return fmt.Errorf("output directory cannot be empty")
	}

	// Create output directory
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	args := []string{"materialize", "--id", snapshotID, "--out", outputDir}
	
	if options.IncludePattern != "" {
		args = append(args, "--include", options.IncludePattern)
	}
	
	if options.ExcludePattern != "" {
		args = append(args, "--exclude", options.ExcludePattern)
	}

	cmd := exec.CommandContext(ctx, hm.binaryPath, args...)
	cmd.Dir = hm.workDir
	
	hm.logger.WithFields(logrus.Fields{
		"command": cmd.String(),
		"snapshot_id": snapshotID,
		"output_dir": outputDir,
		"include": options.IncludePattern,
		"exclude": options.ExcludePattern,
	}).Debug("Executing Helios materialize")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("helios materialize failed: %w, output: %s", err, string(output))
	}

	hm.logger.WithFields(logrus.Fields{
		"snapshot_id": snapshotID,
		"output_dir": outputDir,
	}).Info("Helios materialize completed")

	return nil
}

// Stats retrieves statistics about the Helios storage
func (hm *HeliosManager) Stats(ctx context.Context) (string, error) {
	cmd := exec.CommandContext(ctx, hm.binaryPath, "stats")
	cmd.Dir = hm.workDir
	
	hm.logger.WithField("command", cmd.String()).Debug("Executing Helios stats")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("helios stats failed: %w, output: %s", err, string(output))
	}

	return string(output), nil
}

// Close performs any necessary cleanup
func (hm *HeliosManager) Close() error {
	hm.logger.Info("Helios manager closed")
	return nil
}

// MaterializeOptions defines options for materializing snapshots
type MaterializeOptions struct {
	IncludePattern string `json:"include_pattern"` // Glob pattern for files to include
	ExcludePattern string `json:"exclude_pattern"` // Glob pattern for files to exclude
}

// GetWorkDir returns the working directory path
func (hm *HeliosManager) GetWorkDir() string {
	return hm.workDir
}

// GetBinaryPath returns the helios-cli binary path
func (hm *HeliosManager) GetBinaryPath() string {
	return hm.binaryPath
}

// ValidateConfig validates the Helios configuration
func ValidateHeliosConfig(config HeliosConfig) error {
	if config.BinaryPath == "" {
		return fmt.Errorf("binary_path is required")
	}
	
	if config.WorkDir == "" {
		return fmt.Errorf("work_dir is required")
	}

	// Check if binary exists
	if _, err := os.Stat(config.BinaryPath); os.IsNotExist(err) {
		return fmt.Errorf("helios-cli binary not found at %s", config.BinaryPath)
	}

	// Check if work directory is valid
	if !filepath.IsAbs(config.WorkDir) {
		return fmt.Errorf("work_dir must be an absolute path")
	}

	return nil
}

// DefaultHeliosConfig returns a default Helios configuration
func DefaultHeliosConfig() HeliosConfig {
	return HeliosConfig{
		WorkDir:    "/tmp/helios",
		BinaryPath: "./bin/helios-cli",
	}
}