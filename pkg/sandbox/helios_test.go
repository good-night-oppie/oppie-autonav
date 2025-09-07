// Copyright 2025 Good Night Oppie
// SPDX-License-Identifier: Apache-2.0

package sandbox

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewHeliosManager(t *testing.T) {
	tests := []struct {
		name    string
		config  HeliosConfig
		wantErr bool
	}{
		{
			name: "valid_config",
			config: HeliosConfig{
				BinaryPath: "../../bin/helios-cli",
				WorkDir:    "/tmp/helios-test-valid",
			},
			wantErr: false,
		},
		{
			name: "missing_binary_path",
			config: HeliosConfig{
				WorkDir: "/tmp/helios-test",
			},
			wantErr: true,
		},
		{
			name: "missing_work_dir",
			config: HeliosConfig{
				BinaryPath: "../../bin/helios-cli",
			},
			wantErr: true,
		},
		{
			name: "nonexistent_binary",
			config: HeliosConfig{
				BinaryPath: "/nonexistent/path/helios-cli",
				WorkDir:    "/tmp/helios-test",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Clean up any existing work directory
			if tt.config.WorkDir != "" {
				os.RemoveAll(tt.config.WorkDir)
				defer os.RemoveAll(tt.config.WorkDir)
			}

			hm, err := NewHeliosManager(tt.config)
			
			if tt.wantErr {
				assert.Error(t, err)
				assert.Nil(t, hm)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, hm)
				assert.Equal(t, tt.config.WorkDir, hm.GetWorkDir())
				assert.Equal(t, tt.config.BinaryPath, hm.GetBinaryPath())
				
				// Verify work directory was created
				_, err := os.Stat(tt.config.WorkDir)
				assert.NoError(t, err)
				
				// Clean up
				hm.Close()
			}
		})
	}
}

func TestHeliosManager_Commit(t *testing.T) {
	// Skip if helios-cli binary doesn't exist
	binaryPath := "../../bin/helios-cli"
	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		t.Skip("helios-cli binary not found, skipping integration test")
	}

	workDir := "/tmp/helios-test-commit"
	defer os.RemoveAll(workDir)

	config := HeliosConfig{
		BinaryPath: binaryPath,
		WorkDir:    workDir,
	}

	hm, err := NewHeliosManager(config)
	require.NoError(t, err)
	defer hm.Close()

	// Create some test files in work directory
	testFile := filepath.Join(workDir, "test.txt")
	err = os.WriteFile(testFile, []byte("test content"), 0644)
	require.NoError(t, err)

	ctx := context.Background()
	
	// Test commit
	snapshotID, metrics, err := hm.Commit(ctx, "test commit")
	require.NoError(t, err)
	assert.NotEmpty(t, snapshotID)
	assert.NotNil(t, metrics)
	assert.Greater(t, metrics.CommitTime, time.Duration(0))
	assert.False(t, metrics.OperationTime.IsZero())
}

func TestHeliosManager_CommitRestore(t *testing.T) {
	// Skip if helios-cli binary doesn't exist
	binaryPath := "../../bin/helios-cli"
	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		t.Skip("helios-cli binary not found, skipping integration test")
	}

	workDir := "/tmp/helios-test-restore"
	defer os.RemoveAll(workDir)

	config := HeliosConfig{
		BinaryPath: binaryPath,
		WorkDir:    workDir,
	}

	hm, err := NewHeliosManager(config)
	require.NoError(t, err)
	defer hm.Close()

	ctx := context.Background()

	// Create initial state
	testFile := filepath.Join(workDir, "test.txt")
	originalContent := "original content"
	err = os.WriteFile(testFile, []byte(originalContent), 0644)
	require.NoError(t, err)

	// Create first snapshot
	snapshotID, _, err := hm.Commit(ctx, "initial state")
	require.NoError(t, err)

	// Modify state
	modifiedContent := "modified content"
	err = os.WriteFile(testFile, []byte(modifiedContent), 0644)
	require.NoError(t, err)

	// Verify modification
	content, err := os.ReadFile(testFile)
	require.NoError(t, err)
	assert.Equal(t, modifiedContent, string(content))

	// Restore to original state
	err = hm.Restore(ctx, snapshotID)
	require.NoError(t, err)

	// Verify restoration
	content, err = os.ReadFile(testFile)
	require.NoError(t, err)
	assert.Equal(t, originalContent, string(content))
}

func TestHeliosManager_Diff(t *testing.T) {
	// Skip if helios-cli binary doesn't exist
	binaryPath := "../../bin/helios-cli"
	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		t.Skip("helios-cli binary not found, skipping integration test")
	}

	workDir := "/tmp/helios-test-diff"
	defer os.RemoveAll(workDir)

	config := HeliosConfig{
		BinaryPath: binaryPath,
		WorkDir:    workDir,
	}

	hm, err := NewHeliosManager(config)
	require.NoError(t, err)
	defer hm.Close()

	ctx := context.Background()

	// Create initial state
	testFile := filepath.Join(workDir, "test.txt")
	err = os.WriteFile(testFile, []byte("state 1"), 0644)
	require.NoError(t, err)

	snapshot1, _, err := hm.Commit(ctx, "state 1")
	require.NoError(t, err)

	// Create modified state
	err = os.WriteFile(testFile, []byte("state 2"), 0644)
	require.NoError(t, err)

	snapshot2, _, err := hm.Commit(ctx, "state 2")
	require.NoError(t, err)

	// Test diff
	diff, err := hm.Diff(ctx, snapshot1, snapshot2)
	require.NoError(t, err)
	assert.NotEmpty(t, diff)

	// Test invalid diff parameters
	_, err = hm.Diff(ctx, "", snapshot2)
	assert.Error(t, err)
	
	_, err = hm.Diff(ctx, snapshot1, "")
	assert.Error(t, err)
}

func TestHeliosManager_Materialize(t *testing.T) {
	// Skip if helios-cli binary doesn't exist
	binaryPath := "../../bin/helios-cli"
	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		t.Skip("helios-cli binary not found, skipping integration test")
	}

	workDir := "/tmp/helios-test-materialize"
	outputDir := "/tmp/helios-test-materialize-output"
	defer func() {
		os.RemoveAll(workDir)
		os.RemoveAll(outputDir)
	}()

	config := HeliosConfig{
		BinaryPath: binaryPath,
		WorkDir:    workDir,
	}

	hm, err := NewHeliosManager(config)
	require.NoError(t, err)
	defer hm.Close()

	ctx := context.Background()

	// Create test files
	testFile1 := filepath.Join(workDir, "file1.txt")
	testFile2 := filepath.Join(workDir, "file2.log")
	err = os.WriteFile(testFile1, []byte("content 1"), 0644)
	require.NoError(t, err)
	err = os.WriteFile(testFile2, []byte("content 2"), 0644)
	require.NoError(t, err)

	// Create snapshot
	snapshotID, _, err := hm.Commit(ctx, "test files")
	require.NoError(t, err)

	// Test materialize without filters
	err = hm.Materialize(ctx, snapshotID, outputDir, MaterializeOptions{})
	require.NoError(t, err)

	// Verify materialized files exist
	materializedFile1 := filepath.Join(outputDir, "file1.txt")
	materializedFile2 := filepath.Join(outputDir, "file2.log")
	
	_, err = os.Stat(materializedFile1)
	assert.NoError(t, err)
	_, err = os.Stat(materializedFile2)
	assert.NoError(t, err)

	// Test with include pattern
	outputDir2 := "/tmp/helios-test-materialize-output2"
	defer os.RemoveAll(outputDir2)
	
	err = hm.Materialize(ctx, snapshotID, outputDir2, MaterializeOptions{
		IncludePattern: "*.txt",
	})
	require.NoError(t, err)

	// Verify only .txt file was materialized
	materializedFile1_2 := filepath.Join(outputDir2, "file1.txt")
	materializedFile2_2 := filepath.Join(outputDir2, "file2.log")
	
	_, err = os.Stat(materializedFile1_2)
	assert.NoError(t, err)
	_, err = os.Stat(materializedFile2_2)
	assert.True(t, os.IsNotExist(err)) // Should not exist due to include filter

	// Test error cases
	err = hm.Materialize(ctx, "", outputDir, MaterializeOptions{})
	assert.Error(t, err)
	
	err = hm.Materialize(ctx, snapshotID, "", MaterializeOptions{})
	assert.Error(t, err)
}

func TestHeliosManager_Stats(t *testing.T) {
	// Skip if helios-cli binary doesn't exist
	binaryPath := "../../bin/helios-cli"
	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		t.Skip("helios-cli binary not found, skipping integration test")
	}

	workDir := "/tmp/helios-test-stats"
	defer os.RemoveAll(workDir)

	config := HeliosConfig{
		BinaryPath: binaryPath,
		WorkDir:    workDir,
	}

	hm, err := NewHeliosManager(config)
	require.NoError(t, err)
	defer hm.Close()

	ctx := context.Background()
	
	stats, err := hm.Stats(ctx)
	require.NoError(t, err)
	assert.NotEmpty(t, stats)
}

func TestValidateHeliosConfig(t *testing.T) {
	tests := []struct {
		name    string
		config  HeliosConfig
		wantErr bool
	}{
		{
			name: "valid_config",
			config: HeliosConfig{
				BinaryPath: "../../bin/helios-cli",
				WorkDir:    "/tmp/helios-test",
			},
			wantErr: false,
		},
		{
			name: "missing_binary_path",
			config: HeliosConfig{
				WorkDir: "/tmp/helios-test",
			},
			wantErr: true,
		},
		{
			name: "missing_work_dir",
			config: HeliosConfig{
				BinaryPath: "../../bin/helios-cli",
			},
			wantErr: true,
		},
		{
			name: "relative_work_dir",
			config: HeliosConfig{
				BinaryPath: "../../bin/helios-cli",
				WorkDir:    "relative/path",
			},
			wantErr: true,
		},
		{
			name: "nonexistent_binary",
			config: HeliosConfig{
				BinaryPath: "/nonexistent/path/helios-cli",
				WorkDir:    "/tmp/helios-test",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateHeliosConfig(tt.config)
			
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				// Skip validation if binary doesn't exist (for CI)
				if _, statErr := os.Stat(tt.config.BinaryPath); os.IsNotExist(statErr) {
					t.Skip("helios-cli binary not found, skipping validation test")
				}
				assert.NoError(t, err)
			}
		})
	}
}

func TestDefaultHeliosConfig(t *testing.T) {
	config := DefaultHeliosConfig()
	
	assert.Equal(t, "/tmp/helios", config.WorkDir)
	assert.Equal(t, "../../bin/helios-cli", config.BinaryPath)
}

func TestMaterializeOptions(t *testing.T) {
	opts := MaterializeOptions{
		IncludePattern: "*.txt",
		ExcludePattern: "*.log",
	}
	
	assert.Equal(t, "*.txt", opts.IncludePattern)
	assert.Equal(t, "*.log", opts.ExcludePattern)
}

func TestSnapshotMetrics(t *testing.T) {
	now := time.Now()
	duration := 100 * time.Millisecond
	
	metrics := &SnapshotMetrics{
		CommitTime:    duration,
		ObjectCount:   10,
		DedupRatio:    0.75,
		StorageSize:   1024,
		OperationTime: now,
	}
	
	assert.Equal(t, duration, metrics.CommitTime)
	assert.Equal(t, 10, metrics.ObjectCount)
	assert.Equal(t, 0.75, metrics.DedupRatio)
	assert.Equal(t, int64(1024), metrics.StorageSize)
	assert.Equal(t, now, metrics.OperationTime)
}