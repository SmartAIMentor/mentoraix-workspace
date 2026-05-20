# Bundle Social SKILL.md Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the 969-line `bundle-social-manager` SKILL.md into a ~340-line core + 4 reference files, fixing all incorrect API endpoint paths and field names verified against the Bundle Social OpenAPI spec.

**Architecture:** Extract platform details, upload modes, analytics/webhooks, and error codes into separate reference files under `references/`. Rewrite the core SKILL.md with corrected singular endpoint paths, `create-portal-link` OAuth, `socialAccountTypes` for post creation, and type-based disconnect.

**Tech Stack:** Markdown documentation only — no code changes.

**Base path:** `SmartAIMentor/.claude/skills/bundle-social-manager/`

---

## File Structure

```
SmartAIMentor/.claude/skills/bundle-social-manager/
├── SKILL.md                              (REWRITE — ~340 lines)
└── references/                           (NEW directory)
    ├── platform-details.md               (NEW — extract from SKILL.md:444-716)
    ├── upload-guide.md                   (NEW — extract from SKILL.md:229-312, fix paths)
    ├── analytics-and-webhooks.md         (NEW — extract from SKILL.md:719-858, fix paths)
    └── error-codes.md                    (NEW — extract from SKILL.md:862-914)
```

---

## API Corrections Reference

All corrections below are verified against the Bundle Social OpenAPI spec at `https://api.bundle.social/swagger-json`.

| Current (wrong) | Corrected (verified) |
|---|---|
| `/api/v1/teams` | `/api/v1/team/` |
| `/api/v1/posts` | `/api/v1/post/` |
| `/api/v1/uploads` | `/api/v1/upload/` |
| `/api/v1/social-accounts` | `/api/v1/social-account` |
| `POST /api/v1/social-accounts/connect-url` | `POST /api/v1/social-account/create-portal-link` |
| `socialAccountIds` field | `socialAccountTypes` field |
| `DELETE /.../{socialAccountId}` | `DELETE /api/v1/social-account/disconnect` with body `{type, teamId}` |

---

### Task 1: Create references/ directory and platform-details.md

**Files:**
- Create: `SmartAIMentor/.claude/skills/bundle-social-manager/references/platform-details.md`

- [ ] **Step 1: Create references directory**

```bash
mkdir -p SmartAIMentor/.claude/skills/bundle-social-manager/references
```

- [ ] **Step 2: Create platform-details.md**

Extract lines 444-716 from current SKILL.md (the "Platform-Specific Details" section). This content has NO endpoint paths and needs NO corrections. Write the file with this exact content:

```markdown
> Referenced by SKILL.md. Load when you need the complete field schema or constraints for a specific platform.

## Platform-Specific Details

Each platform has its own schema inside the `platforms` object. Below are the field maps and constraints for all 14 platforms.

### TikTok (`TIKTOK`)

```json
{
  "type": "VIDEO",
  "text": "Caption with #hashtags",
  "uploadIds": ["media_abc123"],
  "thumbnail": "https://cdn.example.com/thumb.jpg",
  "thumbnailOffset": 3.0,
  "privacy": "PUBLIC",
  "isBrandContent": false,
  "isOrganicBrandContent": false,
  "isAiGenerated": false,
  "autoAddMusic": false,
  "disableComments": false,
  "disableDuet": false,
  "disableStitch": false
}
```

- `type`: `"VIDEO"` or `"PHOTO"`. Photos must be JPG (not PNG).
- `privacy`: `"PUBLIC"`, `"MUTUAL_FOLLOW"`, `"FOLLOWER"`, `"SELF_ONLY"`. Default `"PUBLIC"`.
- `isAiGenerated`: Set to `true` for AI-generated or AI-modified content.
- `isBrandContent` / `isOrganicBrandContent`: Declare branded content per TikTok policy.
- `autoAddMusic`: Let TikTok auto-add trending audio to photo posts.
- `thumbnailOffset`: Seconds into the video for the cover frame.

### YouTube (`YOUTUBE`)

```json
{
  "type": "SHORT",
  "uploadIds": ["media_abc123"],
  "text": "Title (required)",
  "description": "Description with links",
  "thumbnail": "https://cdn.example.com/thumb.jpg",
  "privacy": "PUBLIC",
  "madeForKids": false,
  "containsSyntheticMedia": false,
  "hasPaidProductPlacement": false
}
```

- `type`: `"SHORT"` or `"VIDEO"`. Shorts must be vertical and <= 60s.
- `text`: Used as the video title. Required.
- `description`: Video description (optional).
- `privacy`: `"PUBLIC"`, `"UNLISTED"`, `"PRIVATE"`. Default `"PRIVATE"`.
- `madeForKids`: COPPA compliance flag. Required for US audiences.
- `containsSyntheticMedia`: Set `true` if the video uses AI-generated content.
- `hasPaidProductPlacement`: Disclose paid promotions.

### Instagram (`INSTAGRAM`)

```json
{
  "type": "POST",
  "text": "Caption with #hashtags @mentions",
  "uploadIds": ["media_abc123"],
  "thumbnailOffset": 2.5,
  "thumbnail": "https://cdn.example.com/thumb.jpg",
  "shareToFeed": true,
  "collaborators": ["@partner_handle"],
  "tagged": [
    { "username": "@brand", "x": 0.5, "y": 0.5 }
  ]
}
```

- `type`: `"POST"` for Reels/Feed posts.
- `shareToFeed`: Whether to also show the Reel on the main feed.
- `collaborators`: Instagram collab posts. Both accounts must be public.
- `tagged`: User tags with relative coordinates (0.0 - 1.0).
- Recommended aspect ratios: 9:16 for Reels, 1:1 or 4:5 for Feed.
- `thumbnailOffset`: Cover frame position in seconds.

### Facebook (`FACEBOOK`)

```json
{
  "type": "POST",
  "text": "Post text with @mentions",
  "uploadIds": ["media_abc123"],
  "link": "https://example.com",
  "thumbnail": "https://cdn.example.com/thumb.jpg",
  "nativeScheduleTime": "2026-05-18T10:00:00Z"
}
```

- `type`: `"POST"`.
- `link`: Attach a link preview to the post.
- `nativeScheduleTime`: Use Facebook's native scheduling instead of Bundle Social's scheduler.
- Note: Facebook access tokens expire every 60 days. The platform will send a webhook when re-authentication is needed.

### Twitter / X (`TWITTER`)

```json
{
  "text": "Tweet text up to 280 characters",
  "uploadIds": ["media_abc123"]
}
```

- Character limit applies. For longer content, use threads (multiple posts).
- No analytics are available through the Twitter API; use the platform directly.
- No additional type or privacy fields.

### Threads (`THREADS`)

```json
{
  "text": "Post text",
  "uploadIds": ["media_abc123"]
}
```

- Simple schema: text + optional media.
- No privacy controls; all Threads posts are public.

### LinkedIn (`LINKEDIN`)

```json
{
  "text": "Post text with #hashtags",
  "uploadIds": ["media_abc123"],
  "thumbnail": "https://cdn.example.com/thumb.jpg",
  "privacy": "ANYONE",
  "hideFromFeed": false,
  "disableReshare": false
}
```

- `privacy`: `"ANYONE"` (public), `"CONNECTIONS"` (connections only). Default `"ANYONE"`.
- `hideFromFeed`: Prevent the post from appearing on the member's feed.
- `disableReshare`: Disable resharing by others.

### Pinterest (`PINTEREST`)

```json
{
  "boardName": "My Board",
  "text": "Pin title",
  "description": "Pin description",
  "uploadIds": ["media_abc123"],
  "thumbnail": "https://cdn.example.com/thumb.jpg",
  "link": "https://example.com/product",
  "altText": "Image description for accessibility",
  "note": "Internal note",
  "dominantColor": "#FF5733"
}
```

- `boardName`: Required. The pin will be created in this board.
- `link`: Destination URL when users click the pin.
- `altText`: Accessibility description; also used for Pinterest search.
- `dominantColor`: Background color for the pin card.

### Reddit (`REDDIT`)

```json
{
  "sr": "subreddit_name",
  "text": "Post title",
  "description": "Post body (markdown)",
  "uploadIds": ["media_abc123"],
  "link": "https://example.com",
  "nsfw": false,
  "flairId": "flair_abc123"
}
```

- `sr`: Subreddit name (without the `r/` prefix). Required.
- `nsfw`: Mark as NSFW.
- `flairId`: Post flair ID from the subreddit's available flairs.
- Reddit has strict self-promotion rules; advise the user to follow the 10:1 rule.

### Mastodon (`MASTODON`)

```json
{
  "text": "Toot text",
  "uploadIds": ["media_abc123"],
  "thumbnail": "https://cdn.example.com/thumb.jpg",
  "privacy": "PUBLIC",
  "spoiler": ""
}
```

- `privacy`: `"PUBLIC"`, `"UNLISTED"`, `"PRIVATE"`, `"DIRECT"`. Default `"PUBLIC"`.
- `spoiler`: Content warning text. If non-empty, the toot is hidden behind a CW.

### Discord (`DISCORD`)

```json
{
  "channelId": "1234567890",
  "text": "Message text",
  "uploadIds": ["media_abc123"],
  "username": "Bot Display Name",
  "avatarUrl": "https://cdn.example.com/avatar.png"
}
```

- `channelId`: Required. The Discord channel to post in.
- `username` / `avatarUrl`: Override the webhook bot's display name and avatar for this message.
- Requires a webhook integration set up in the Discord channel.

### Slack (`SLACK`)

```json
{
  "channelId": "C01234567",
  "text": "Message text",
  "uploadIds": ["media_abc123"],
  "username": "Bot Display Name",
  "avatarUrl": "https://cdn.example.com/avatar.png"
}
```

- `channelId`: Required. The Slack channel ID.
- Same webhook pattern as Discord.

### Bluesky (`BLUESKY`)

```json
{
  "text": "Post text",
  "uploadIds": ["media_abc123"],
  "tags": ["tech", "ai"],
  "labels": ["!warn"],
  "quoteUri": "at://did:plc:.../app.bsky.feed.post/...",
  "externalUrl": "https://example.com",
  "externalTitle": "Link Title",
  "externalDescription": "Link description",
  "videoAlt": "Video description for accessibility"
}
```

- `tags`: Array of hashtag-like tags.
- `labels`: Content labels for moderation (e.g., `!warn` for adult content).
- `quoteUri`: AT URI of the post being quoted.
- `externalUrl` / `externalTitle` / `externalDescription`: Link card attachment.
- `videoAlt`: Alt text for video media.

### Google Business Profile (`GOOGLE_BUSINESS`)

```json
{
  "text": "Post text",
  "uploadIds": ["media_abc123"],
  "topicType": "STANDARD",
  "languageCode": "en",
  "callToActionType": "BOOK",
  "callToActionUrl": "https://example.com/book",
  "eventTitle": "Grand Opening",
  "eventStartDate": "2026-06-01T10:00:00Z",
  "eventEndDate": "2026-06-01T18:00:00Z",
  "offerCouponCode": "SAVE20",
  "offerRedeemOnlineUrl": "https://example.com/redeem",
  "offerTermsConditions": "Valid for 30 days",
  "alertType": "COVID_19"
}
```

- `topicType`: `"STANDARD"`, `"EVENT"`, `"OFFER"`, `"ALERT"`. Determines which additional fields are required.
- `callToActionType`: `"BOOK"`, `"ORDER"`, `"SHOP"`, `"LEARN_MORE"`, `"SIGN_UP"`, `"CALL"`, `"VISIT"`.
- When `topicType` is `"EVENT"`, provide `eventTitle`, `eventStartDate`, `eventEndDate`.
- When `topicType` is `"OFFER"`, provide `offerCouponCode`, `offerRedeemOnlineUrl`, `offerTermsConditions`.
- `alertType`: `"COVID_19"`, `"HOLIDAY"`, `"REOPEN"`, etc.
```

- [ ] **Step 3: Verify file created**

```bash
wc -l SmartAIMentor/.claude/skills/bundle-social-manager/references/platform-details.md
```

Expected: ~270 lines

- [ ] **Step 4: Commit**

```bash
git add SmartAIMentor/.claude/skills/bundle-social-manager/references/platform-details.md
git commit -m "docs: extract platform details to references/platform-details.md"
```

---

### Task 2: Create references/upload-guide.md

**Files:**
- Create: `SmartAIMentor/.claude/skills/bundle-social-manager/references/upload-guide.md`

- [ ] **Step 1: Create upload-guide.md**

Extract from current SKILL.md lines 229-312 with endpoint path corrections (plural → singular) and verified sub-endpoints. Write:

```markdown
> Referenced by SKILL.md. Load when you need URL-Based Upload or Chunked Upload (Direct Upload is documented in the core file).

## Upload Modes

### Direct Upload (files <= 90 MB)

```
POST /api/v1/upload/
Content-Type: multipart/form-data

teamId: team_abc123
file: <binary>
```

Response:

```json
{
  "id": "media_abc123",
  "url": "https://cdn.bundle.social/...",
  "status": "READY",
  "mimeType": "video/mp4",
  "sizeBytes": 5242880
}
```

### URL-Based Upload

Provide a publicly accessible URL instead of uploading binary data:

```
POST /api/v1/upload/from-url
Content-Type: application/json

{
  "teamId": "team_abc123",
  "url": "https://example.com/video.mp4"
}
```

Same response shape as direct upload.

### Chunked Upload (files > 90 MB)

1. Initialize the upload:

```
POST /api/v1/upload/init
Content-Type: application/json

{
  "teamId": "team_abc123",
  "fileName": "long_video.mp4",
  "fileSize": 524288000,
  "mimeType": "video/mp4"
}
```

Response:

```json
{
  "uploadId": "chunked_abc123",
  "chunkSize": 10485760,
  "totalChunks": 50
}
```

2. Upload each chunk (repeat for all chunks):

```
PUT /api/v1/upload/{uploadId}/chunk/{chunkIndex}
Content-Type: application/octet-stream

<binary chunk data>
```

3. Finalize:

```
POST /api/v1/upload/finalize
Content-Type: application/json

{
  "uploadId": "chunked_abc123",
  "teamId": "team_abc123"
}
```

Returns the standard media response with `id`, `url`, `status`.
```

- [ ] **Step 2: Verify no plural endpoint paths remain**

```bash
grep -n '/uploads' SmartAIMentor/.claude/skills/bundle-social-manager/references/upload-guide.md
```

Expected: no output (0 matches)

- [ ] **Step 3: Commit**

```bash
git add SmartAIMentor/.claude/skills/bundle-social-manager/references/upload-guide.md
git commit -m "docs: extract upload guide to references/upload-guide.md with corrected endpoints"
```

---

### Task 3: Create references/analytics-and-webhooks.md

**Files:**
- Create: `SmartAIMentor/.claude/skills/bundle-social-manager/references/analytics-and-webhooks.md`

- [ ] **Step 1: Create analytics-and-webhooks.md**

Extract from current SKILL.md lines 719-858. Add Phase 2 note. No endpoint path corrections needed (analytics/webhook endpoints don't use plural forms in the current SKILL.md). Write:

```markdown
> Referenced by SKILL.md. Load when you need analytics data, webhook configuration, or webhook event handling.
>
> **Phase 2**: Analytics and Webhooks are not in the current implementation scope (see integration design doc "后续扩展"). This reference is provided for future development.

## Analytics

### Get Analytics

```
GET /api/v1/analytics?teamId=team_abc123&platform=TIKTOK&timeframe=30d&limit=20&offset=0
```

Parameters:
- `teamId` (required)
- `platform`: Filter by platform enum
- `postResultId[]`: Filter by specific post result IDs (pass multiple for OR logic)
- `timeframe`: `7d`, `30d`, `90d`, `all`. Default `all`.
- `limit` / `offset`: Pagination

Response:

```json
{
  "data": [
    {
      "postResultId": "pp_001",
      "platform": "TIKTOK",
      "viewCount": 12450,
      "likeCount": 892,
      "commentCount": 47,
      "shareCount": 128,
      "coverImageUrl": "https://...",
      "shareUrl": "https://tiktok.com/@user/video/123",
      "duration": 15.5,
      "postedAt": "2026-05-10T12:00:00Z"
    }
  ],
  "total": 42,
  "offset": 0,
  "limit": 20
}
```

Note: Twitter/X does not provide analytics through the API.

### Sync Analytics

Manually trigger a sync from platforms:

```
POST /api/v1/analytics/sync?teamId=team_abc123
```

Optionally filter by platform:

```
POST /api/v1/analytics/sync?teamId=team_abc123&platform=INSTAGRAM
```

Rate-limited to once every 5 minutes per team.

---

## Webhooks

### Register a Webhook

```
POST /api/v1/webhooks
Content-Type: application/json

{
  "url": "https://your-server.com/webhook",
  "events": ["post.posted", "post.failed", "post.scheduled"]
}
```

Response:

```json
{
  "id": "wh_abc123",
  "url": "https://your-server.com/webhook",
  "events": ["post.posted", "post.failed", "post.scheduled"],
  "secret": "whsec_...",
  "createdAt": "2026-05-17T10:00:00Z"
}
```

Store the `secret`; it is used to verify webhook signatures.

### Webhook Event Types

| Event | Trigger |
|---|---|
| `post.posted` | Post successfully published to a platform |
| `post.failed` | Post failed to publish |
| `post.scheduled` | Post scheduled for future publishing |
| `post.deleted` | Post deleted |
| `post.processing` | Post entered processing state |
| `post.review` | Post pending platform review |
| `social_account.connected` | New social account linked |
| `social_account.disconnected` | Social account unlinked |
| `social_account.token_expired` | OAuth token expired; re-auth needed |

### Webhook Payload

```json
{
  "event": "post.posted",
  "timestamp": "2026-05-17T14:00:05Z",
  "data": {
    "postId": "post_abc123",
    "platformPostId": "pp_001",
    "platform": "TIKTOK",
    "status": "POSTED",
    "teamId": "team_abc123"
  }
}
```

### Signature Verification

Every webhook request includes an `x-signature` header containing an HMAC-SHA256 of the raw request body using the webhook `secret` as the key.

Verify in your handler:

```python
import hmac, hashlib

def verify_signature(body: bytes, signature: str, secret: str) -> bool:
    expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)
```

### List / Delete Webhooks

```
GET /api/v1/webhooks
```

```
DELETE /api/v1/webhooks/{webhookId}
```
```

- [ ] **Step 2: Verify file created**

```bash
wc -l SmartAIMentor/.claude/skills/bundle-social-manager/references/analytics-and-webhooks.md
```

Expected: ~110 lines

- [ ] **Step 3: Commit**

```bash
git add SmartAIMentor/.claude/skills/bundle-social-manager/references/analytics-and-webhooks.md
git commit -m "docs: extract analytics and webhooks to references/ with Phase 2 note"
```

---

### Task 4: Create references/error-codes.md

**Files:**
- Create: `SmartAIMentor/.claude/skills/bundle-social-manager/references/error-codes.md`

- [ ] **Step 1: Create error-codes.md**

Extract from current SKILL.md lines 862-914. No endpoint corrections needed. Write:

```markdown
> Referenced by SKILL.md. Load when encountering an API error that needs diagnosis.

## Error Handling

All errors follow a consistent format:

```json
{
  "error": {
    "code": "TT_CONTENT_REJECTED",
    "message": "TikTok rejected the video due to policy violation.",
    "details": {}
  }
}
```

Error codes are prefixed by platform:

| Prefix | Platform |
|---|---|
| `META_` | Instagram, Facebook, Threads |
| `TT_` | TikTok |
| `TW_` | Twitter / X |
| `LI_` | LinkedIn |
| `YT_` | YouTube |
| `GB_` | Google Business |
| `PIN_` | Pinterest |
| `RD_` | Reddit |
| `DI_` | Discord |
| `SL_` | Slack |
| `BSKY_` | Bluesky |
| `MST_` | Mastodon |
| `HTTP_` | Generic HTTP errors |
| `NET_` | Network / connectivity errors |

Common error codes:

| Code | HTTP | Meaning |
|---|---|---|
| `HTTP_UNAUTHORIZED` | 401 | Invalid or missing API key |
| `HTTP_FORBIDDEN` | 403 | API key lacks permission for this operation |
| `HTTP_NOT_FOUND` | 404 | Resource not found |
| `HTTP_VALIDATION_ERROR` | 400 | Request body failed validation |
| `HTTP_RATE_LIMITED` | 429 | Rate limit exceeded |
| `HTTP_MONTHLY_LIMIT` | 429 | Monthly post cap reached |
| `TT_CONTENT_REJECTED` | 400 | TikTok rejected the content |
| `META_MEDIA_FORMAT` | 400 | Instagram/Facebook media format issue |
| `YT_QUOTA_EXCEEDED` | 429 | YouTube API quota exhausted |

Recovery strategy:
- `401`: Check API key value and header name (`x-api-key`).
- `429` rate limit: Wait and retry using the `Retry-After` header.
- `429` monthly cap: Upgrade the plan or wait for next billing cycle.
- Platform-specific `4xx`: Fix the request per the error message; do not retry without changes.
- `5xx` / `NET_` errors: Retry with exponential backoff (max 3 retries).
```

- [ ] **Step 2: Verify file created**

```bash
wc -l SmartAIMentor/.claude/skills/bundle-social-manager/references/error-codes.md
```

Expected: ~50 lines

- [ ] **Step 3: Commit**

```bash
git add SmartAIMentor/.claude/skills/bundle-social-manager/references/error-codes.md
git commit -m "docs: extract error codes to references/error-codes.md"
```

---

### Task 5: Rewrite SKILL.md core

**Files:**
- Modify: `SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md` (complete rewrite)

This is the main task. The entire file is replaced with the restructured core content. All endpoint paths are corrected to singular form. The `socialAccountIds` → `socialAccountTypes` fix, `connect-url` → `create-portal-link` fix, and type-based disconnect are applied.

- [ ] **Step 1: Write the new SKILL.md**

Write the complete file. The content is provided below — every line is specified:

```markdown
---
name: bundle-social-manager
version: 1.1.0
title: Social Media Manager (via Bundle Social)
description: >
  Manage social media posting for CreatorPilot via the Bundle Social API.
  Handles team-based multi-user isolation, OAuth account connection (hosted portal),
  media upload, cross-platform posting/scheduling, and post status tracking.
  Use when the task involves publishing to TikTok, Instagram, YouTube, Twitter/X,
  or any of the 14 supported platforms.
license: MIT
author: CreatorPilot
homepage: https://bundle.social
repository: https://info.bundle.social
keywords:
  - social-media
  - automation
  - bundle-social
  - tiktok
  - instagram
  - youtube
  - twitter
  - linkedin
  - posting
  - scheduling
metadata:
  openclaw:
    requires:
      env:
        - BUNDLE_SOCIAL_API_KEY
    primaryEnv: BUNDLE_SOCIAL_API_KEY
---

# Social Media Manager (via Bundle Social)

Post, schedule, and manage content across 14 platforms through the [Bundle Social](https://bundle.social) API.

## Supported Platforms

| Platform | Enum | Post types |
|---|---|---|
| TikTok | `TIKTOK` | video, photo (JPG only) |
| YouTube | `YOUTUBE` | SHORT or VIDEO |
| Instagram | `INSTAGRAM` | POST (Reels/Stories via type field) |
| Facebook | `FACEBOOK` | POST |
| Twitter / X | `TWITTER` | text + media |
| Threads | `THREADS` | text + media |
| LinkedIn | `LINKEDIN` | text + media |
| Pinterest | `PINTEREST` | pin with board |
| Reddit | `REDDIT` | post to subreddit |
| Mastodon | `MASTODON` | toot |
| Discord | `DISCORD` | channel message |
| Slack | `SLACK` | channel message |
| Bluesky | `BLUESKY` | post with rich metadata |
| Google Business | `GOOGLE_BUSINESS` | local post with CTA |

Platform-specific field schemas and constraints are in `references/platform-details.md`.

---

## Setup

1. Create an account at [bundle.social](https://bundle.social)
2. Create an organization, then at least one team inside it
3. Connect social accounts via the hosted portal flow (see step 2 below)
4. Generate an API key from the dashboard (format: `pk_live_...`)
5. Store the key in your workspace `.env`:
   ```
   BUNDLE_SOCIAL_API_KEY=pk_live_xxxxx
   ```

---

## Authentication

All requests require one header:

```
x-api-key: <BUNDLE_SOCIAL_API_KEY>
```

There is no Bearer token. The API key authenticates at the organization level; most endpoints also require a `teamId` to scope operations to a specific team.

Base URL: `https://api.bundle.social`

---

## Organization & Team Hierarchy

Bundle Social uses a two-level model:

- **Organization** (org): owns API keys, billing, webhooks, monthly post caps
- **Team**: owns social accounts, posts, and day-to-day operations

Most endpoints require a `teamId` parameter. A single org can have multiple teams, each with its own connected accounts and posting schedule.

### List Teams

```
GET /api/v1/team/
```

Response:

```json
[
  {
    "id": "team_abc123",
    "name": "Marketing Team",
    "organizationId": "org_xyz789",
    "createdAt": "2026-01-15T10:00:00Z"
  }
]
```

### Create Team

```
POST /api/v1/team/
Content-Type: application/json

{
  "name": "creator_abc123"
}
```

Response:

```json
{
  "id": "team_xyz789",
  "name": "creator_abc123",
  "organizationId": "org_abc123",
  "createdAt": "2026-05-17T12:00:00Z"
}
```

---

## Rate Limits

Rate limits apply per team:

| Window | Limit |
|---|---|
| Burst | 100 requests / sec |
| Short | 500 requests / 10 sec |
| Sustained | 2,000 requests / min |

Monthly post caps by plan:

| Plan | Posts / month |
|---|---|
| FREE | 10 |
| PRO | 1,000 |
| BUSINESS | 100,000 |

Rate limit headers are returned on every response:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 94
X-RateLimit-Reset: 1716300000
```

When rate-limited, the API returns HTTP 429 with body:

```json
{
  "error": {
    "code": "HTTP_RATE_LIMITED",
    "message": "Rate limit exceeded. Retry after 2 seconds."
  }
}
```

---

## Core Workflow

### 1. List or Create Teams

```
GET /api/v1/team/
```

Returns all teams in your organization. Store a `teamId` for subsequent calls. If no team exists for a user, create one:

```
POST /api/v1/team/
Content-Type: application/json

{
  "name": "creator_abc123"
}
```

### 2. Connect Social Accounts (Hosted Portal)

Generate a hosted OAuth portal link for the user to authorize platforms:

```
POST /api/v1/social-account/create-portal-link
Content-Type: application/json

{
  "teamId": "team_abc123",
  "redirectUrl": "https://app.creatorpilot.com/social/callback",
  "socialAccountTypes": ["TIKTOK", "INSTAGRAM"]
}
```

Response:

```json
{
  "url": "https://app.bundle.social/connect?token=...",
  "expiresAt": "2026-05-17T12:00:00Z"
}
```

The user opens this URL in a browser, completes the OAuth flow on Bundle Social's hosted page, and the account is automatically linked to the team. After completion, the user is redirected to `redirectUrl`.

### 3. List Connected Social Accounts

Get all accounts for a team:

```
GET /api/v1/social-account?teamId=team_abc123
```

Or look up a specific account by platform type:

```
GET /api/v1/social-account/by-type?type=TIKTOK&teamId=team_abc123
```

Response:

```json
[
  {
    "id": "sa_001",
    "platform": "TIKTOK",
    "username": "@creator_handle",
    "teamId": "team_abc123",
    "connectedAt": "2026-03-10T14:00:00Z",
    "status": "ACTIVE"
  }
]
```

### 4. Disconnect a Social Account

Disconnect by platform type (not by account ID):

```
DELETE /api/v1/social-account/disconnect
Content-Type: application/json

{
  "type": "TIKTOK",
  "teamId": "team_abc123"
}
```

### 5. Upload Media

Direct upload for files up to 90 MB:

```
POST /api/v1/upload/
Content-Type: multipart/form-data

teamId: team_abc123
file: <binary>
```

Response:

```json
{
  "id": "media_abc123",
  "url": "https://cdn.bundle.social/...",
  "status": "READY",
  "mimeType": "video/mp4",
  "sizeBytes": 5242880
}
```

For URL-based upload and chunked upload (files > 90 MB), see `references/upload-guide.md`.

### 6. Create a Post

```
POST /api/v1/post/
Content-Type: application/json
```

**Multi-platform post:**

```json
{
  "teamId": "team_abc123",
  "socialAccountTypes": ["TIKTOK", "INSTAGRAM"],
  "postNow": true,
  "platforms": {
    "TIKTOK": {
      "text": "Check out this new product! #tiktokmademebuyit",
      "uploadIds": ["media_abc123"],
      "type": "VIDEO"
    },
    "INSTAGRAM": {
      "text": "New drop alert! #reels",
      "uploadIds": ["media_abc123"],
      "type": "POST"
    }
  }
}
```

**Scheduled post:**

```json
{
  "teamId": "team_abc123",
  "socialAccountTypes": ["TIKTOK"],
  "postNow": false,
  "scheduleDate": "2026-05-18T14:00:00Z",
  "platforms": {
    "TIKTOK": {
      "text": "Scheduled post",
      "uploadIds": ["media_abc123"],
      "type": "VIDEO"
    }
  }
}
```

Response:

```json
{
  "id": "post_abc123",
  "teamId": "team_abc123",
  "status": "POSTED",
  "platformPosts": [
    {
      "id": "pp_001",
      "platform": "TIKTOK",
      "status": "POSTED",
      "platformPostId": "7123456789",
      "postedAt": "2026-05-17T14:00:05Z"
    },
    {
      "id": "pp_002",
      "platform": "INSTAGRAM",
      "status": "PROCESSING",
      "platformPostId": null,
      "postedAt": null
    }
  ],
  "createdAt": "2026-05-17T14:00:00Z"
}
```

**Note:** The field is `socialAccountTypes` (platform enum strings like `"TIKTOK"`, `"INSTAGRAM"`), not `socialAccountIds`. Per-platform configs go inside the `platforms` object keyed by platform enum. See `references/platform-details.md` for all platform schemas.

### 7. Get Post Status / List Posts

```
GET /api/v1/post/{postId}?teamId=team_abc123
```

```
GET /api/v1/post/?teamId=team_abc123&limit=20&offset=0
```

Optional filters: `status`, `platform`, `socialAccountId`.

### 8. Update a Scheduled Post

```
PATCH /api/v1/post/{postId}
Content-Type: application/json

{
  "teamId": "team_abc123",
  "scheduleDate": "2026-05-19T10:00:00Z",
  "platforms": {
    "TIKTOK": {
      "text": "Updated caption"
    }
  }
}
```

Only posts with status `DRAFT` or `SCHEDULED` can be updated.

### 9. Delete a Post

```
DELETE /api/v1/post/{postId}?teamId=team_abc123
```

Only works on posts with status `DRAFT` or `SCHEDULED`.

---

## Post Statuses

| Status | Meaning |
|---|---|
| `DRAFT` | Created but not scheduled or published |
| `SCHEDULED` | Queued for future publishing |
| `POSTED` | Successfully published to platform |
| `PROCESSING` | Upload or platform processing in progress |
| `REVIEW` | Pending platform review (e.g., TikTok review) |
| `RETRYING` | Transient failure, automatic retry in progress |
| `ERROR` | Failed to post; check `errorMessage` |
| `DELETED` | Deleted by user |

---

## Recommended Workflow

### For a single post

1. Get or create team: `GET /api/v1/team/` or `POST /api/v1/team/`
2. Get social accounts: `GET /api/v1/social-account?teamId=<id>&platform=<platform>`
3. Upload media: `POST /api/v1/upload/` (direct, URL, or chunked)
4. Create post: `POST /api/v1/post/` with `postNow: true`
5. Poll status: `GET /api/v1/post/{postId}?teamId=<id>` until status is `POSTED` or `ERROR`

### For scheduled batches

1. Same steps 1-3 above
2. Create posts with `postNow: false` and a `scheduleDate`
3. Optionally register a webhook for `post.posted` / `post.failed` events (see `references/analytics-and-webhooks.md`)
4. Check analytics after 24-48 hours

### For multi-platform posting

1. Upload media once (reuse the `uploadId` across platforms)
2. In the `POST /api/v1/post/` body, include all target platforms in `socialAccountTypes`
3. Use the `platforms` object to customize caption, type, and settings per platform
4. Check per-platform status in the `platformPosts` array of the response

### For video content pipeline

1. Store videos in a local folder
2. Extract a frame with ffmpeg for cover thumbnail analysis:
   ```
   ffmpeg -i video.mp4 -ss 00:00:03 -frames:v 1 frame.jpg -y
   ```
3. Upload the video and optional thumbnail
4. Create the post with platform-specific configs
5. Move posted videos to a `posted/` subfolder to avoid duplicates
6. Track performance with analytics endpoint

---

## References

| File | When to load |
|------|-------------|
| `references/platform-details.md` | Need the complete field schema or constraints for a specific platform |
| `references/upload-guide.md` | Need URL-Based Upload or Chunked Upload (Direct Upload is documented above) |
| `references/analytics-and-webhooks.md` | Need analytics data, webhook configuration, or event handling (Phase 2) |
| `references/error-codes.md` | Encountering an API error that needs diagnosis |

---

## Tips

- Post to multiple platforms simultaneously by including multiple types in `socialAccountTypes` and per-platform configs in `platforms`
- Stagger posts throughout the day (e.g., 9am + 12pm + 6pm in the audience timezone) for better reach
- Reuse `uploadId` across platforms to avoid uploading the same file multiple times
- Use `DRAFT` status to stage content and `PATCH` to update before scheduling
- TikTok `SELF_ONLY` privacy is useful for testing before publishing publicly
- YouTube Shorts must be vertical (9:16) and under 60 seconds
- Instagram Reels should be 9:16; Feed posts can be 1:1 or 4:5
- Facebook tokens expire every 60 days; monitor `social_account.token_expired` webhooks
- Reddit enforces self-promotion limits; advise 10:1 organic-to-promotional ratio
- For files over 90 MB, always use the chunked upload flow (see `references/upload-guide.md`)
- Keep hashtags to 4-5 per post for TikTok and Instagram for best engagement
- Set up webhooks to avoid polling for post status (see `references/analytics-and-webhooks.md`)
```

- [ ] **Step 2: Verify no incorrect endpoint paths remain**

```bash
grep -En '/(posts|uploads|social-accounts|connect-url)' SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
```

Expected: no output (0 matches)

```bash
grep -n 'socialAccountIds' SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
```

Expected: no output (0 matches)

- [ ] **Step 3: Verify singular endpoint paths present**

```bash
grep -c '/api/v1/post' SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
grep -c '/api/v1/upload' SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
grep -c '/api/v1/social-account' SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
grep -c '/api/v1/team' SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
grep -c 'create-portal-link' SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
grep -c 'socialAccountTypes' SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
```

Expected: each returns >= 1 match

- [ ] **Step 4: Verify version and frontmatter**

```bash
head -5 SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
```

Expected: `version: 1.1.0` on line 3

- [ ] **Step 5: Verify line count**

```bash
wc -l SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
```

Expected: ~340 lines

- [ ] **Step 6: Commit**

```bash
git add SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
git commit -m "docs: rewrite SKILL.md core with verified API endpoints and restructured layout"
```

---

### Task 6: Final validation

- [ ] **Step 1: Verify all files exist**

```bash
ls -la SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md
ls -la SmartAIMentor/.claude/skills/bundle-social-manager/references/platform-details.md
ls -la SmartAIMentor/.claude/skills/bundle-social-manager/references/upload-guide.md
ls -la SmartAIMentor/.claude/skills/bundle-social-manager/references/analytics-and-webhooks.md
ls -la SmartAIMentor/.claude/skills/bundle-social-manager/references/error-codes.md
```

Expected: all 5 files exist

- [ ] **Step 2: Global scan for incorrect API patterns across all files**

```bash
grep -rn '/posts' SmartAIMentor/.claude/skills/bundle-social-manager/
grep -rn '/uploads' SmartAIMentor/.claude/skills/bundle-social-manager/
grep -rn '/social-accounts' SmartAIMentor/.claude/skills/bundle-social-manager/
grep -rn 'connect-url' SmartAIMentor/.claude/skills/bundle-social-manager/
grep -rn 'socialAccountIds' SmartAIMentor/.claude/skills/bundle-social-manager/
```

Expected: all return 0 matches

- [ ] **Step 3: Verify cross-references are valid**

```bash
grep -o 'references/[^)]*\.md' SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md | while read f; do
  if [ ! -f "SmartAIMentor/.claude/skills/bundle-social-manager/$f" ]; then
    echo "MISSING: $f"
  fi
done
```

Expected: no output (all referenced files exist)

- [ ] **Step 4: Final commit with tag**

```bash
git add SmartAIMentor/.claude/skills/bundle-social-manager/
git commit --allow-empty -m "docs: complete bundle-social-manager SKILL.md restructure v1.1.0"
```
