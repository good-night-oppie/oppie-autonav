# Claude Workflow Test Document

This document demonstrates the Claude self-hosted review workflow.

## Test Features

### 1. Interactive Review
- Comment `@claude` on the PR to trigger review
- Claude will analyze the changes and provide feedback

### 2. Automatic Review
- Triggered automatically on PR open/sync
- Complexity detection adjusts review depth

### 3. Manual Trigger
- Use GitHub Actions UI to manually trigger reviews
- Select review type: quick, standard, or thorough

## Workflow Status

✅ **All secrets configured:**
- CLAUDE_ACCESS_TOKEN
- CLAUDE_REFRESH_TOKEN  
- CLAUDE_TOKEN_EXPIRY
- CLAUDE_CODE_OAUTH_TOKEN

✅ **Workflows ready:**
- claude-self-hosted.yml
- claude-pr-review.yml
- claude-interactive.yml

## Testing Checklist

- [ ] Create PR
- [ ] Comment with @claude mention
- [ ] Verify Claude responds
- [ ] Check review quality
- [ ] Test manual trigger

---
*This is a test document to demonstrate the Claude workflow capabilities.*